/*
 * vim: sts=4 sw=4 ts=8 et
 *
 *      File            :   Pcm.xs                       
 *      
 *      Description     :   Perl XS module performing PCM_OP via hashtables ($in can be string):
 *                          ($out, $ebuf) = Pcm::op($opcode, $flags, $in)
 *      
 *      Version         :   1.00 beta
 *                          
 *      Created         :   20.06.2013
 *
 *      Updated         :   26.07.2013 
 *      
 *      Author          :   Tomasz Budzen, Accenture (tomasz.budzen@accenture.com)
 *                          
 *      Notes           :   Module depends of -lportal and -lpcmext.
 *                          We use only PIN memory management (pin_malloc(), pin_free() and pin_strdup()).
 *                          We allow indices for both array and substruct fields and also simple fields.
 *                          Module implements type checking. 
 *                          NULL decimals, timestamps, POIDs and strings are converted to (undef) instead of 0 and "".
 *                          Conversion of PIN_FLDT_OBJ and PIN_FLDT_TEXTBUF types is not implemented.
 *							To croak use ppcm_croak() wrapper.
 *
 *      Changes         :   Corrected enum, timestamp and binstr types.
 *                          Corrected memory leaks and indexed substructs.
 * 							Corrected NULL and (undef) handling.
 *
 *		To do 			:  	Udostêpnienie nazw opkodów, jako sta³ych w przestrzeni nazw Pcm, np.: 
 *							Pcm::PCM_OP_WRITE_FLDS. 
 *
 *							Lista opkodów powinna byæ budowana dynamicznie (--> ops/_.h)
 *
 *							PCM_OPREF()
 *
 */

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"
#include <pin_type.h>
#include <pcm.h>

/*****************************************************************************************
 * 
 * 		Global variables
 *
 ***************************************************************************************** 
 */

int64 g_database = 0;
pcm_context_t * g_ctxt = NULL;
pin_errbuf_t g_err_buffer;
char g_str_buffer [1024];
char g_msg_str_buffer [1024];
char * g_log_filename;
int32 * g_log_level;

/*****************************************************************************************
 * 
 * 		Global utility structures & functions
 *
 ***************************************************************************************** 
 */

typedef struct he_data // Decomposed HE (hashtable entry) (to improve readability)
{
    char * key_str;
    SV * value;
    svtype type;
    int is_hashtable;
    pin_fld_num_t pin_num;
    pin_fld_type_t pin_type;
    int pin_is_complex_type; 
    int we_have_index;
    int index;
} 
he_data_t;

pin_flist_t * ppcm_ht_to_fl(HV * ht, pin_flist_t * parent_fl, he_data_t * parent_he_data);
void ppcm_ht_to_fl_elems(HV * ht, pin_flist_t * parent_fl, he_data_t * parent_he_data, int indexed_simple_field);
void ppcm_ht_to_fl_elem(HE * he, pin_flist_t * parent_fl, he_data_t * parent_he_data, int indexed_simple_field);
poid_t * ppcm_ht_to_fl_poid(HV * ht);
HV * ppcm_eb_to_ht(pin_errbuf_t * eb);
HV * ppcm_fl_to_ht(pin_flist_t * fl);
int ppcm_is_indexed_simple_field(pin_flist_t * fl, pin_fld_num_t fld_num, pin_fld_num_t fld_type);
SV * ppcm_ptr_to_sv(void * p, pin_fld_type_t fld_type);
void ppcm_decompose_ht_entry(HE * he, he_data_t * he_data);
void ppcm_check_type(he_data_t * he_data, pin_fld_type_t type);
char * ppcm_pin_type_to_str(pin_fld_type_t type);
char * ppcm_perl_type_to_str(svtype type);
static inline char * ppcm_poid_db_to_str(int64 db);
static inline char * ppcm_int_to_str(int n);
static inline SV * ppcm_newSVpv(char * s);
static inline SV * ppcm_deref(SV * sv);
static inline void ppcm_hv_store(HV * ht, char * fld_name, SV * sv);
void ppcm_croak(const char * msg, ...);

/*****************************************************************************************
 * 
 *      Error messages
 *
 ***************************************************************************************** 
 */

#define     PCM_HELLO_MSG                                   "Hello world and PCM (db = %d) :-).\n"

#define     ERR_MSG_CONNECTION_FAILURE                      "failed to connect"
#define     ERR_MSG_INVALID_OPCODE                          "invalid opcode"
#define     ERR_MSG_INVALID_SIZE_OF_POID                    "invalid POID hashtable size"
#define     ERR_MSG_INVALID_STRUCTURE_OF_POID               "invalid POID hashtable structure"
#define     ERR_MSG_INVALID_TYPE_IN_POID                    "invalid type in POID hashtable"
#define     ERR_MSG_INVALID_REFERENCE_TYPE                  "invalid reference type"
#define     ERR_MSG_INVALID_REFERENCE                       "invalid reference"
#define     ERR_MSG_INVALID_ENTRY_KEY                       "invalid entry key"
#define     ERR_MSG_INVALID_FIELD_TYPE                      "invalid field type"
#define     ERR_MSG_INVALID_ARRAY_STRUCTURE                 "invalid array hashtable structure"
#define     ERR_MSG_INVALID_SUBSTRUCT_HASHTABLE_STRUCTURE   "invalid substruct hashtable structure"
#define     ERR_MSG_ARRAY_ELEMENT_IN_SUBSTRUCT              "array element in substructure"
#define     ERR_MSG_CONFLICTING_TYPE                        "conflicting type"
#define     ERR_MSG_SUBSTRUCT_IN_ARRAY                      "substruct in array"
#define     ERR_MSG_NO_INDEX_FOR_ARRAY_ELEMENT              "no index for array element"
#define     ERR_MSG_NO_INDEX_FOR_INDEXED_NORMAL_FIELD       "no index for indexed normal field"
#define     ERR_MSG_NON_INDEXED_FIELD_IN_INDEXED_SUBSTRUCT  "no index for indexed substruct element"
#define     ERR_MSG_UNABLE_TO_CREATE_POID                   "unable to create POID"
#define     ERR_MSG_ALLOCATION_OF_FL_FAILED                 "failed to allocate flist"
#define     ERR_MSG_UNABLE_TO_FREE_FLIST                    "unable to free flist"
#define     ERR_MSG_CONVERSION_OF_HT_FAILED                 "conversion of hashtable failed"
#define     ERR_MSG_CONVERSION_OF_UNKNOWN_PIN_TYPE          "conversion of unknown PIN type"
#define     ERR_MSG_CONVERSION_NOT_IMPLEMENTED              "conversion of PIN_FLDT_OBJ, PIN_FLDT_TEXTBUF not implemented"
#define     ERR_MSG_OBSOLETE_TYPE                           "conversion of obsolete type PIN_FLDT_NUM"
#define		ERR_MSG_FILE_BUF_NOT_SUPPORTED					"file-backed PIN_FLDT_BUF is not supported"
#define     ERR_MSG_NEGATIVE_ARRAY_IDX                      "negative index in array"
#define     ERR_MSG_NULL_FLIST                              "NULL flist pointer"
#define     ERR_MSG_NULL_HASHTABLE                          "NULL hashtable pointer"
#define		ERR_MSG_NULL_HASHENTRY							"NULL hashtable entry pointer"
#define     ERR_MSG_NULL_EBUF                               "NULL error buffer pointer"
#define     ERR_MSG_NULL_OUT_FL                             "NULL output flist pointer"
#define     ERR_MSG_PIN_FLIST_TO_STR_FAILED                 "PIN_FLIST_TO_STR() failed"
#define     ERR_MSG_FLD_SET_FAILED                          "PIN_FLIST_FLD_SET() failed"
#define     ERR_MSG_FLD_PUT_FAILED                          "PIN_FLIST_FLD_PUT() failed"
#define     ERR_MSG_ELEM_ADD_FAILED                         "PIN_FLIST_ELEM_ADD() failed"
#define     ERR_MSG_ELEM_SET_FAILED                         "PIN_FLIST_ELEM_SET() failed"
#define     ERR_MSG_ELEM_PUT_FAILED                         "PIN_FLIST_ELEM_PUT() failed"
#define     ERR_MSG_SUBSTR_SET_FAILED                       "PIN_FLIST_SUBSTR_SET() failed"
#define     ERR_MSG_SUBSTR_ADD_FAILED                       "PIN_FLIST_SUBSTR_ADD() failed"
#define     ERR_MSG_ANY_GET_NEXT_FAILED                     "PIN_FLIST_ANY_GET_NEXT() failed"
#define     ERR_MSG_PIN_POID_FROM_STR_FAILED                "PIN_POID_FROM_STR() failed"
#define     ERR_MSG_PIN_POID_CREATE_FAILED                  "PIN_POID_CREATE() failed"
#define		ERR_MSG_STR_TO_FLIST_FAILED						"PIN_STR_TO_FLIST() failed"
#define     ERR_MSG_PBO_DECIMAL_TO_DOUBLE_FAILED            "pbo_decimal_to_double() failed"
#define     ERR_MSG_PBO_DECIMAL_FROM_DOUBLE_FAILED          "pbo_decimal_from_double() failed"
#define		ERR_MSG_PBO_DECIMAL_FROM_STR_FAILED				"pbo_decimal_from_str() failed"
#define     ERR_MSG_FL_PRINT_FAILED                         "pin_flist_print() failed"
#define		ERR_MSG_PIN_CONF_FAILED							"pin_conf() failed"

//**************************************************************************************** 
        
void ppcm_croak(const char * msg, ...) 
{   
    va_list v;
    
    va_start(v, msg);
    memset(g_msg_str_buffer, 0, sizeof(g_msg_str_buffer));
    strcpy(g_msg_str_buffer, "[Pcm error: ");
    strcat(g_msg_str_buffer, msg);
    strcat(g_msg_str_buffer, "]");
    vsnprintf(g_str_buffer, sizeof(g_str_buffer), g_msg_str_buffer, v);
    va_end(v);
    PIN_ERR_LOG_MSG(g_log_level, g_str_buffer);
    PIN_ERR_LOG_EBUF(g_log_level, "[Pcm PIN error buffer]", & g_err_buffer);
    croak(g_str_buffer);
};

char * ppcm_pin_type_to_str(pin_fld_type_t type)
{
    switch(type)
    {
        case PIN_FLDT_INT : return "PIN_FLDT_INT";
        case PIN_FLDT_UINT : return "PIN_FLDT_UINT";
        case PIN_FLDT_ENUM : return "PIN_FLDT_ENUM";
        case PIN_FLDT_NUM : return "PIN_FLDT_NUM"; // Obsolete, not implemented
        case PIN_FLDT_STR : return "PIN_FLDT_STR";
        case PIN_FLDT_BUF : return "PIN_FLDT_BUF";
        case PIN_FLDT_POID : return "PIN_FLDT_POID";
        case PIN_FLDT_TSTAMP : return "PIN_FLDT_TSTAMP";
        case PIN_FLDT_ARRAY : return "PIN_FLDT_ARRAY";
        case PIN_FLDT_SUBSTRUCT : return "PIN_FLDT_SUBSTRUCT";
        case PIN_FLDT_BINSTR : return "PIN_FLDT_BINSTR";
        case PIN_FLDT_ERRBUF : return "PIN_FLDT_ERRBUF";
        case PIN_FLDT_DECIMAL : return "PIN_FLDT_DECIMAL";
        case PIN_FLDT_TIME : return "PIN_FLDT_TIME"; 
        case PIN_FLDT_OBJ : return "PIN_FLDT_OBJ"; // Not implemented
        case PIN_FLDT_TEXTBUF : return "PIN_FLDT_TEXTBUF"; // Not implemented
        default : return NULL;
    };
};

static inline SV * ppcm_newSVpv(char * s)
{
    return (s ? newSVpv(s, strlen(s)) : newSV(0)); 
};

static inline SV * ppcm_deref(SV * sv)
{
	return (SvROK(sv) ? SvRV(sv) : sv);
};

static inline void ppcm_hv_store(HV * ht, char * fld_name, SV * sv)
{
	ppcm_hv_store(ht, fld_name, strlen(fld_name), sv, 0);  
};

/*
 *      Constructs POID from Perl hashtable with optional revision entry. 
 *      
 *      PIN_POID_FROM_STR() because of possible poid revision entry,
 *      F.e.: { "db" => "0.0.0.2", "type" => "/dummy", "id" => 0, "rev" => 52345321 }
 *
 */

poid_t * ppcm_ht_to_fl_poid(HV * ht)
{
    poid_t * result = NULL;
    SV * poid_db_sv = NULL;
    SV * poid_type_sv = NULL;
    SV * poid_id_sv = NULL;
    SV * poid_rev_sv = NULL;    
    char * poid_db = NULL;
    char * poid_type = NULL;
    int64 poid_id = 0;
    int64 poid_rev = 0;
    int size = 0;
    
    if( ! ht) ppcm_croak(ERR_MSG_NULL_HASHTABLE);
    PIN_ERRBUF_CLEAR( & g_err_buffer);
    size = hv_iterinit(ht);
    if(size == 3 || size == 4)
    {
        if
        ( 
            ! hv_exists(ht, "db", 2) || 
            ! hv_exists(ht, "type", 4) ||
            ! hv_exists(ht, "id", 2) || 
            (size == 4 && ! hv_exists(ht, "rev", 3))
        ) 
        {
            ppcm_croak(ERR_MSG_INVALID_STRUCTURE_OF_POID);
        };
        
        poid_db_sv = ppcm_deref(*(hv_fetch(ht, "db", 2, 0)));
        if((SvTYPE(poid_db_sv) == SVt_PV || SvTYPE(poid_db_sv) == SVt_PVIV) && SvPOK(poid_db_sv))
        { 
        	poid_db = SvPV_nolen(poid_db_sv); 
        }
        else 
        {
        	ppcm_croak("%s: db: %s", ERR_MSG_INVALID_TYPE_IN_POID, ppcm_perl_type_to_str(SvTYPE(poid_db_sv)));   
        };
        
        poid_type_sv = ppcm_deref(*(hv_fetch(ht, "type", 4, 0))); 
        if((SvTYPE(poid_type_sv) == SVt_PV || SvTYPE(poid_type_sv) == SVt_PVIV) && SvPOK(poid_type_sv)) 
        {
        	poid_type = SvPV_nolen(poid_type_sv); 
        }
        else 
        {
        	ppcm_croak("%s: type: %s", ERR_MSG_INVALID_TYPE_IN_POID, ppcm_perl_type_to_str(SvTYPE(poid_type_sv)));
        };	
        
        poid_id_sv = ppcm_deref(*(hv_fetch(ht, "id", 2, 0))); 
        if((SvTYPE(poid_id_sv) == SVt_IV || SvTYPE(poid_id_sv) == SVt_PVIV) && SvIOK(poid_id_sv)) 
        {
        	poid_id = SvIV(poid_id_sv); 
        }
        else 
        {
        	ppcm_croak("%s: id: %s", ERR_MSG_INVALID_TYPE_IN_POID, ppcm_perl_type_to_str(SvTYPE(poid_id_sv)));
		};

        if(size == 4)
        {
            poid_rev_sv = ppcm_deref(*(hv_fetch(ht, "rev", 3, 0))); 
            if((SvTYPE(poid_id_sv) == SVt_IV || SvTYPE(poid_id_sv) == SVt_PVIV) && SvIOK(poid_rev_sv)) 
            {
                poid_rev = SvIV(poid_rev_sv); 
            }
            else 
            {
                ppcm_croak("%s: rev: %s", ERR_MSG_INVALID_TYPE_IN_POID, ppcm_perl_type_to_str(SvTYPE(poid_rev_sv)));
            };
        };
        
        snprintf(g_str_buffer, sizeof(g_str_buffer), "%s %s %d %d", poid_db, poid_type, (int) poid_id, (int) poid_rev);
        result = PIN_POID_FROM_STR(g_str_buffer, (char **) (g_str_buffer + (strlen(g_str_buffer)) * sizeof(char *)), & g_err_buffer);
        if(PIN_ERRBUF_IS_ERR( & g_err_buffer))
        {
            ppcm_croak("%s: \"%s\"", ERR_MSG_PIN_POID_FROM_STR_FAILED, g_str_buffer);
        };
    }
    else
    {
        ppcm_croak("%s: %d", ERR_MSG_INVALID_SIZE_OF_POID, size);
    };
    return result;
};

/*
 *      Converts Perl hashtable to flist.
 * 
 *      Creates flist, iterates over hashtable, 
 *      calling ppcm_ht_to_fl_elems() for complex types or indexed simple values 
 *      or ppcm_ht_to_fl_elem() for non-indexed simple values.
 */

pin_flist_t * ppcm_ht_to_fl(HV * ht, pin_flist_t * parent_fl, he_data_t * parent_he_data)
{
    pin_flist_t * fl = NULL;
    pin_flist_t * substruct_fl = NULL;
    HE * he = NULL;
    HE * tmp_he = NULL;
    he_data_t he_data;
    he_data_t tmp_he_data;
    int indexed_simple_field = 0;
    
    if( ! ht) ppcm_croak(ERR_MSG_NULL_HASHTABLE);
    PIN_ERRBUF_CLEAR( & g_err_buffer);
    fl = PIN_FLIST_CREATE( & g_err_buffer);
    if(PIN_ERRBUF_IS_ERR( & g_err_buffer)) ppcm_croak(ERR_MSG_ALLOCATION_OF_FL_FAILED); 
    if(hv_iterinit(ht) == 0) // Empty hashtable -> so we assume empty array at parent_fl
    {       
        PIN_FLIST_ELEM_PUT(parent_fl, fl, parent_he_data->pin_num, 0, & g_err_buffer); // Index = 0
        if(PIN_ERRBUF_IS_ERR( & g_err_buffer)) ppcm_croak(ERR_MSG_ELEM_SET_FAILED);
    }
    else
    {
        while((he = hv_iternext(ht)))
        {
            ppcm_decompose_ht_entry(he, & he_data);
            indexed_simple_field = 
                he_data.is_hashtable &
                (
                    (he_data.pin_type != PIN_FLDT_BUF) &
                    (he_data.pin_type != PIN_FLDT_ERR) &
                    (he_data.pin_type != PIN_FLDT_ARRAY) & 
                    (he_data.pin_type != PIN_FLDT_SUBSTRUCT) &
                    (he_data.pin_type != PIN_FLDT_POID)
                );
            if(he_data.pin_is_complex_type || indexed_simple_field) // Array, substruct or indexed simple field
            {
                if(he_data.pin_type == PIN_FLDT_SUBSTRUCT) 
                {
                    if(he_data.is_hashtable) // We check first sub-element to know whether substruct is indexed or not
                    {                              
                        hv_iterinit((HV *) he_data.value);
                        tmp_he = hv_iternext((HV *) he_data.value);
                        ppcm_decompose_ht_entry(tmp_he, & tmp_he_data);
                        if(tmp_he_data.we_have_index) // To avoid creating SUBSTRUCT [0] on flist for indexed substructs
                        {
                			substruct_fl = fl;
                        }
                        else
                        {
                            substruct_fl = PIN_FLIST_SUBSTR_ADD(fl, he_data.pin_num, & g_err_buffer);
                            if(PIN_ERRBUF_IS_ERR( & g_err_buffer)) ppcm_croak(ERR_MSG_SUBSTR_ADD_FAILED);
                        };
                    	ppcm_ht_to_fl_elems( (HV *) he_data.value, substruct_fl, & he_data, indexed_simple_field);
                    }
                    else
                    {
        				PIN_FLIST_SUBSTR_SET(fl, NULL, he_data.pin_num, & g_err_buffer); 
                    };
                }
                else
                {
                	if(he_data.type == SVt_NULL)
                	{
        				PIN_FLIST_ELEM_SET(fl, NULL, he_data.pin_num, 0, & g_err_buffer); 
                        if(PIN_ERRBUF_IS_ERR( & g_err_buffer)) ppcm_croak(ERR_MSG_SUBSTR_ADD_FAILED);
                	}
                	else
                	{
                    	ppcm_ht_to_fl_elems( (HV *) he_data.value, fl, & he_data, indexed_simple_field);
                   	};
                };
            }
            else // Simple element or POID
            {
                ppcm_ht_to_fl_elem(he, fl, & he_data, 0);
            };
        };        
    }; 
    return fl;
};

char * ppcm_perl_type_to_str(svtype type)
{
    switch(type)
    {     
        case SVt_NULL : return "undef";
        case SVt_IV : return "integer";
        case SVt_NV : return "double";
        case SVt_RV : return "reference";
        case SVt_PV : return "string";
        case SVt_PVIV : return "integer_or_string";
        case SVt_PVNV : return "double_or_string";
        case SVt_PVMG : return "normal_scalar";
        case SVt_PVGV : return "typeglob";
        case SVt_PVLV : return "delegate";
        case SVt_PVAV : return "array";
        case SVt_PVHV : return "hashtable";
        case SVt_PVCV : return "subroutine";
        case SVt_PVFM : return "format";
        case SVt_PVIO : return "I/O_object";
        // case SVt_BIND : return "bind";
        // case SVt_REGEXP : return "regexp";
        default : return NULL;  
    };
};

/*
 *      Checks hashtable entry type-consistency against PIN type.
 * 
 *      Every simple field can be indexed also (he_data->is_hashtable).
 * 
 */

void ppcm_check_type(he_data_t * he_data, pin_fld_type_t type)
{
    int is_valid = 0;
    
    if(type)
    {
        switch(type)
        {
            case PIN_FLDT_STR :
            case PIN_FLDT_BINSTR :
            
                is_valid = he_data->is_hashtable || (he_data->type == SVt_PV && SvPOK(he_data->value));
                break;
                
            case PIN_FLDT_INT :
            case PIN_FLDT_UINT :
            case PIN_FLDT_ENUM :
            case PIN_FLDT_TSTAMP :
            
                is_valid = he_data->is_hashtable || ((he_data->type == SVt_IV || he_data->type == SVt_PVIV) && SvIOK(he_data->value));
                break;
            
            case PIN_FLDT_DECIMAL :
            
                is_valid = he_data->is_hashtable || (he_data->type == SVt_NULL) || ((he_data->type == SVt_NV || he_data->type == SVt_PVNV) && SvNOK(he_data->value));
                break;
                
            case PIN_FLDT_POID :
            case PIN_FLDT_ARRAY :
            case PIN_FLDT_SUBSTRUCT :
            
                is_valid = he_data->is_hashtable || (he_data->type == SVt_NULL);
                break;
                
            case PIN_FLDT_BUF :
            case PIN_FLDT_ERR :
            
                is_valid = he_data->is_hashtable;
                break;

            case PIN_FLDT_NUM :
            case PIN_FLDT_TEXTBUF :
            case PIN_FLDT_OBJ :
            case PIN_FLDT_TIME :
            default :
            
                is_valid = 0;
                break;
        };
    }
    else // type == 0
    {
        is_valid = 1;
    };
    
    if( ! is_valid) 
    {
        ppcm_croak
        (
            "%s: (%s) <-> %s (%s)", 
            ERR_MSG_CONFLICTING_TYPE, 
            ppcm_perl_type_to_str(he_data->type), 
            he_data->key_str,
            ppcm_pin_type_to_str(he_data->pin_type)
        );
    };
};

/*
 *      Decomposes hashtable entry and sets additional flags (f.e. PIN type).
 * 
 *      We assume that key must be integer or string (cannot be hashtable).
 * 
 */

void ppcm_decompose_ht_entry(HE * he, he_data_t * he_data)
{
    char * end_ptr = NULL;
    I32 dummy_len = 0;

    he_data->key_str = hv_iterkey(he, & dummy_len);
    he_data->value = ppcm_deref(HeVAL(he)); // Dereferencing to check type
    he_data->type = SvTYPE(he_data->value);
    he_data->is_hashtable = (he_data->type == SVt_PVHV);
    he_data->pin_num = pin_field_of_name(he_data->key_str); // Valid if not index
    he_data->pin_type = pin_type_of_field(he_data->pin_num);
    he_data->index = strtol(he_data->key_str, & end_ptr, 10);
    he_data->we_have_index = (he_data->key_str != end_ptr || strcmp(he_data->key_str, "*") == 0);
    if(he_data->index < 0) ppcm_croak("%s: %s", ERR_MSG_NEGATIVE_ARRAY_IDX, he_data->key_str);
    if(strcmp(he_data->key_str, "*") == 0) he_data->index = 0;
    he_data->pin_is_complex_type = 
    	(
    		he_data->pin_type == PIN_FLDT_ARRAY || 
    		he_data->pin_type == PIN_FLDT_SUBSTRUCT
    	);
};

/*
 *      We assume that hash entry was validated with ppcm_check_type().
 *      Values are later PUT to flist, not SET.
 *      Can return NULL.
 * 
 */

// pcm.h: typedef enum pin_enum { X, Y } pin_enum_t;

void * ppcm_he_value(he_data_t * he_data)
{
    void * result = NULL;
    int32 * value_I = NULL;
    time_t * value_T = NULL;
    pin_enum_t * value_E = NULL;
    pin_binstr_t * value_BSTR = NULL;
    STRLEN value_BSTR_str_len = 0;   
    
    switch(he_data->type)
    {             
        case SVt_IV :
        case SVt_PVIV :
        
            if(he_data->pin_type == PIN_FLDT_TSTAMP) 
            {
                value_T = pin_malloc(sizeof(time_t));
                *value_T = SvIV(he_data->value);
                result = value_T;
            }
            else if(he_data->pin_type == PIN_FLDT_ENUM)
            {
                value_E = pin_malloc(sizeof(pin_enum_t));
                *value_E = SvIV(he_data->value);
                result = value_E;
            }
            else
            {
                value_I = pin_malloc(sizeof(int32)); 
                *value_I = SvIV(he_data->value); 
                result = value_I; 
            };
            break;
        
        case SVt_NV : 
        case SVt_PVNV :
        
            result = pbo_decimal_from_double(SvNV(he_data->value), & g_err_buffer);
            if(PIN_ERRBUF_IS_ERR( & g_err_buffer)) ppcm_croak(ERR_MSG_PBO_DECIMAL_FROM_DOUBLE_FAILED);  
            break;

        case SVt_PV : 
        
            if(he_data->pin_type == PIN_FLDT_BINSTR) 
            {
            	if(he_data->value)
            	{
                	value_BSTR = pin_malloc(sizeof(pin_binstr_t));
                	value_BSTR->data = pin_strdup(SvPV(he_data->value, value_BSTR_str_len));
               	 	value_BSTR->size = value_BSTR_str_len;
                	result = value_BSTR;
                }
                else
                {
                	result = NULL;
                };
            }
            else
            {
                result = pin_strdup(SvPV_nolen(he_data->value)); 
            };
            break;

        case SVt_NULL : // Undef for simple type
        
        	if(he_data->pin_type == PIN_FLDT_DECIMAL)
            {
            	result = pbo_decimal_from_str("NULL", & g_err_buffer);
            	if(PIN_ERRBUF_IS_ERR( & g_err_buffer)) ppcm_croak(ERR_MSG_PBO_DECIMAL_FROM_STR_FAILED);  
            }
            else
            { 
            	result = NULL;
            };
            break;

        // case SVt_BIND :
        // case SVt_REGEXP :             
        case SVt_RV : 
        case SVt_PVMG :
        case SVt_PVGV : 
        case SVt_PVLV : 
        case SVt_PVAV : 
        case SVt_PVHV : 
        case SVt_PVCV : 
        case SVt_PVFM : 
        case SVt_PVIO : 
        default : 
        
            result = NULL; // We should croak here
            break;  
    };  
    return result;
};

/*
 *      Called from ppcm_ht_to_fl().
 * 
 *      We can have index or not:
 *      1) In arrays there _must_ be indices.
 *      2) In substructs there _can_ be indices.
 *
 */

void ppcm_ht_to_fl_elems(HV * ht, pin_flist_t * parent_fl, he_data_t * parent_he_data, int indexed_simple_field)
{
    pin_flist_t * fl = NULL;
    HE * he = NULL;
    he_data_t he_data;
    
    if( ! ht) ppcm_croak(ERR_MSG_NULL_HASHTABLE); 
    PIN_ERRBUF_RESET( & g_err_buffer);   
    if(hv_iterinit(ht) == 0) // Empty hashtable -> so we assume empty array at parent_fl
    {       
        fl = PIN_FLIST_CREATE( & g_err_buffer);
        if(PIN_ERRBUF_IS_ERR( & g_err_buffer)) ppcm_croak(ERR_MSG_ALLOCATION_OF_FL_FAILED);  
        PIN_FLIST_ELEM_PUT(parent_fl, fl, parent_he_data->pin_num, 0, & g_err_buffer); // Index = 0
        if(PIN_ERRBUF_IS_ERR( & g_err_buffer)) ppcm_croak(ERR_MSG_ELEM_SET_FAILED);
    }
    else
    {
        while((he = hv_iternext(ht)))
        {            
            ppcm_decompose_ht_entry(he, & he_data);            
            if(parent_he_data->pin_type == PIN_FLDT_ARRAY && ! he_data.we_have_index) 
            {
                ppcm_croak("%s: %s", ERR_MSG_SUBSTRUCT_IN_ARRAY, pin_name_of_field(parent_he_data->pin_num));
            };
            ppcm_ht_to_fl_elem(he, parent_fl, parent_he_data, indexed_simple_field);            
        };
    };
};

/*
 *      Called from ppcm_ht_to_fl() or ppcm_ht_to_fl_elems().
 *
 *      Does conversion, or calls ppcm_ht_to_fl() in case of complex types,
 *      then sets element of flist.
 *
 *		Yes, I know it's messy :-)
 *      
 */

void ppcm_ht_to_fl_elem(HE * he, pin_flist_t * parent_fl, he_data_t * parent_he_data, int indexed_simple_field)
{
    pin_flist_t * elem_fl = NULL;
    void * elem_value_ptr = NULL;
    he_data_t he_data;
    
    if( ! he) ppcm_croak(ERR_MSG_NULL_HASHENTRY); 
    PIN_ERRBUF_CLEAR( & g_err_buffer);  
      
    ppcm_decompose_ht_entry(he, & he_data);    
    ppcm_check_type( & he_data, he_data.pin_type); 

    // A) Getting element value or element flist - elem_value_ptr can be NULL
    
    if(he_data.is_hashtable)
    {
        if(he_data.pin_type == PIN_FLDT_POID)
        {
        	if(he_data.type != SVt_NULL)
        	{
        		elem_value_ptr = ppcm_ht_to_fl_poid( (HV *) he_data.value);
           	}
           	else
           	{
           		elem_value_ptr = NULL;
           	};
        }
        else
        {
            elem_fl = ppcm_ht_to_fl( (HV *) he_data.value, parent_fl, parent_he_data);
        };
    }
    else
    {
        elem_value_ptr = ppcm_he_value( & he_data);  
    };

    // B) Creating element flist for elem_value_ptr in case of complex fields
    
    if
    ( 
    	! elem_fl && 
    	(
    		(parent_he_data->pin_type == PIN_FLDT_ARRAY) || 
    		(parent_he_data->pin_type == PIN_FLDT_SUBSTRUCT && he_data.we_have_index)
    	)
    ) 
    {
        elem_fl = PIN_FLIST_CREATE( & g_err_buffer);
        if(PIN_ERRBUF_IS_ERR( & g_err_buffer)) ppcm_croak(ERR_MSG_ALLOCATION_OF_FL_FAILED);  
        if(elem_value_ptr)
        {
            PIN_FLIST_FLD_PUT(elem_fl, he_data.pin_num, elem_value_ptr, & g_err_buffer); // To avoid memory leaks 
            if(PIN_ERRBUF_IS_ERR( & g_err_buffer)) ppcm_croak(ERR_MSG_FLD_PUT_FAILED);      
        };
    };
    
    // C) Putting element value or element flist
    
    if(indexed_simple_field) // We PUT elem_value_ptr
    {
        if(he_data.we_have_index)
        {
            PIN_FLIST_ELEM_PUT(parent_fl, elem_value_ptr, parent_he_data->pin_num, he_data.index, & g_err_buffer);   
            if(PIN_ERRBUF_IS_ERR( & g_err_buffer)) ppcm_croak("%s: %s", ERR_MSG_ELEM_PUT_FAILED, he_data.key_str);           
        }
        else
        {
            ppcm_croak(ERR_MSG_NO_INDEX_FOR_INDEXED_NORMAL_FIELD);
        };
    }
    else if(parent_he_data->pin_type == PIN_FLDT_ARRAY) // We PUT elem_fl
    {
        if(he_data.we_have_index)
        {
            PIN_FLIST_ELEM_PUT(parent_fl, elem_fl, parent_he_data->pin_num, he_data.index, & g_err_buffer);    
            if(PIN_ERRBUF_IS_ERR( & g_err_buffer)) ppcm_croak("%s: %s", ERR_MSG_ELEM_PUT_FAILED, he_data.key_str);           
        }
        else
        {
            ppcm_croak(ERR_MSG_NO_INDEX_FOR_ARRAY_ELEMENT);
        };
    }
    else if(parent_he_data->pin_type == PIN_FLDT_SUBSTRUCT) // We PUT elem_fl or elem_value_ptr
    {
        if(he_data.we_have_index) // We put indexed element on flist parent_fl
        {
            PIN_FLIST_ELEM_PUT(parent_fl, elem_fl, parent_he_data->pin_num, he_data.index, & g_err_buffer);    
            if(PIN_ERRBUF_IS_ERR( & g_err_buffer)) ppcm_croak("%s: %s", ERR_MSG_ELEM_PUT_FAILED, he_data.key_str);           
        }
        else // We put non-indexed field on substruct parent_fl
        {
            PIN_FLIST_FLD_PUT(parent_fl, he_data.pin_num, elem_value_ptr, & g_err_buffer);  
            if(PIN_ERRBUF_IS_ERR( & g_err_buffer)) ppcm_croak("%s: %s", ERR_MSG_FLD_PUT_FAILED, he_data.key_str);           
        };
    }
    else // Simple field without index
    { 
        switch(parent_he_data->pin_type) // Should be consistent with he_data.pin_type, PUT to avoid memory leaks
        {            
            case PIN_FLDT_STR : 
            case PIN_FLDT_POID : 
            case PIN_FLDT_INT : 
            case PIN_FLDT_UINT : 
            case PIN_FLDT_ENUM : 
            case PIN_FLDT_DECIMAL :
            case PIN_FLDT_TSTAMP :  
            case PIN_FLDT_BINSTR:
            
                PIN_FLIST_FLD_PUT(parent_fl, parent_he_data->pin_num, elem_value_ptr, & g_err_buffer); 
                if(PIN_ERRBUF_IS_ERR( & g_err_buffer)) ppcm_croak("%s: %s", ERR_MSG_FLD_PUT_FAILED, he_data.key_str); 
                break;         
                
            case PIN_FLDT_NUM :
            
                ppcm_croak(ERR_MSG_OBSOLETE_TYPE);
                break;
                
            default :
            
                ppcm_croak("%s: %s", ERR_MSG_INVALID_ENTRY_KEY, parent_he_data->key_str);
                break;
        };
    };
};

static inline char * ppcm_poid_db_to_str(int64 db)
{
    _pin_poid_print_db(db, g_str_buffer);
    return pin_strdup(g_str_buffer);
};

static inline char * ppcm_int_to_str(int n)
{
    snprintf(g_str_buffer, sizeof(g_str_buffer), "%d", n);
    return pin_strdup(g_str_buffer);
};

/*
 *      Converts error buffer to Perl hashtable.
 * 
 *      We don't convert location, class & err to names, 
 *      because of possible custom setting of error buffer.
 *
 */

HV * ppcm_eb_to_ht(pin_errbuf_t * eb)
{
    HV * ht = NULL;

    if( ! eb) ppcm_croak(ERR_MSG_NULL_EBUF);
    ht = newHV();
    ppcm_hv_store(ht, "location", newSViv(eb->location));
    ppcm_hv_store(ht, "class", newSViv(eb->pin_errclass));
    ppcm_hv_store(ht, "err", newSViv(eb->pin_err));
    ppcm_hv_store(ht, "field", newSViv(eb->field));
    ppcm_hv_store(ht, "rec_id", newSViv(eb->rec_id));
    ppcm_hv_store(ht, "reserved", newSViv(eb->reserved));
    ppcm_hv_store(ht, "line_no", newSViv(eb->line_no));
    ppcm_hv_store(ht, "filename", ppcm_newSVpv( (char *) eb->filename));
    ppcm_hv_store(ht, "facility", newSViv(eb->facility));
    ppcm_hv_store(ht, "msg_id", newSViv(eb->msg_id));
    ppcm_hv_store(ht, "err_time_sec", newSViv(eb->err_time_sec));
    ppcm_hv_store(ht, "err_time_usec", newSViv(eb->err_time_usec));
    ppcm_hv_store(ht, "version", newSViv(eb->version));
    ppcm_hv_store(ht, "args", (eb->argsp ? (SV *) ppcm_fl_to_ht(eb->argsp) : newRV( (SV *) newSV(0))));
    ppcm_hv_store(ht, "reserved2", newSViv(eb->reserved2));
    ppcm_hv_store(ht, "next", (eb->nextp ? (SV *) ppcm_eb_to_ht(eb->nextp) : newRV( (SV *) newSV(0))));
    return ht;
};

/*
 *      Creates SV value from (void *) according to PIN field type. 
 * 
 */

SV * ppcm_ptr_to_sv(void * p, pin_fld_type_t fld_type)
{
    HV * binstr_ht = NULL;
    SV * sv_value = NULL;
    pin_buf_t * sub_buf = NULL;
    pin_binstr_t * sub_binstr = NULL;
    double double_value;
    
    switch(fld_type) 
    {
        case PIN_FLDT_STR : 
        
            sv_value = ppcm_newSVpv( (char *) p);
            break;

        case PIN_FLDT_INT :
        case PIN_FLDT_UINT :
        case PIN_FLDT_ENUM :
        case PIN_FLDT_TSTAMP : 
        
            sv_value = newSViv( *(int *) p);
            break;                 

        case PIN_FLDT_TIME : 
        
            sv_value = newSViv( *(time_t *) p);
            break;
            
        case PIN_FLDT_DECIMAL : 
        
            PIN_ERRBUF_RESET( & g_err_buffer);
            if( ! pbo_decimal_is_null( (pin_decimal_t *) p, & g_err_buffer))
            {
                double_value = pbo_decimal_to_double( (pin_decimal_t *) p, & g_err_buffer);
                if(PIN_ERRBUF_IS_ERR(& g_err_buffer)) ppcm_croak("%s: %s %p", ERR_MSG_PBO_DECIMAL_TO_DOUBLE_FAILED, pin_pinerr_to_str(g_err_buffer.pin_err), p);
                sv_value = newSVnv(double_value);
            }
            else
            {
                sv_value = newRV(newSV(0));
            };
            break;
            
        case PIN_FLDT_BUF :
        
            sub_buf = (pin_buf_t *) p;
            if(sub_buf)
            {
                if(sub_buf->flag)
                {
                    ppcm_croak(ERR_MSG_FILE_BUF_NOT_SUPPORTED);     
                }
                else
                {
                    sv_value = newSVpvn(sub_buf->data, sub_buf->size);
                };
            }
            else
            {
                sv_value = newRV(newSV(0));
            };
            break;
            
        case PIN_FLDT_ERRBUF :
        
            sv_value = (p ? (SV *) ppcm_eb_to_ht( (pin_errbuf_t *) p) : newRV(newSV(0)));
            break;

        case PIN_FLDT_BINSTR :
        
            sub_binstr = (pin_binstr_t *) p;
            if(sub_binstr)
            {
                binstr_ht = newHV();
                ppcm_hv_store(binstr_ht, "size", newSViv(sub_binstr->size));
                ppcm_hv_store(binstr_ht, "data", ppcm_newSVpv( (char *) sub_binstr->data));
                sv_value = (SV *) binstr_ht;   
            }
            else
            {
                sv_value = newRV(newSV(0));
            };     
            break;
            
        case PIN_FLDT_NUM :
        
            ppcm_croak(ERR_MSG_OBSOLETE_TYPE);
            break;
            
        default :
        
            ppcm_croak(ERR_MSG_CONVERSION_OF_UNKNOWN_PIN_TYPE);
            break;
    }; 
    return sv_value;
};

int ppcm_is_indexed_simple_field(pin_flist_t * fl, pin_fld_num_t fld_num, pin_fld_num_t fld_type)
{
    pin_flist_t * tmp_fl = NULL;
    pin_rec_id_t tmp_rec_id = 0;
    pin_cookie_t tmp_cookie = NULL;
    int result = 0;
    
    tmp_rec_id = -1;
    tmp_cookie = NULL;
    tmp_fl = PIN_FLIST_ELEM_GET_NEXT(fl, fld_num, & tmp_rec_id, 0, & tmp_cookie, & g_err_buffer);
    result = 
        tmp_rec_id & // Indexed if tmp_rec_id > 0
        (
            (fld_type != PIN_FLDT_ARRAY) & 
            (fld_type != PIN_FLDT_SUBSTRUCT) &
            (fld_type != PIN_FLDT_POID)
        );
    return result;
};

/*
 *      Converts given flist to Perl hashtable.
 *
 */

HV * ppcm_fl_to_ht(pin_flist_t * fl)
{
    HV * ht = NULL;
    HV * sub_ht = NULL;
    HV * sub_ht_2 = NULL;
    HV * poid_ht = NULL;
    pin_rec_id_t rec_id = 0;
    pin_rec_id_t rec_id_2 = 0;
    pin_cookie_t cookie = NULL;
    pin_cookie_t cookie_2 = NULL;
    pin_fld_num_t fld_num;
    char * fld_name = NULL;
    pin_fld_num_t fld_type;
    pin_flist_t * sub_fl = NULL;
    pin_flist_t * array_sub_fl = NULL;
    pin_flist_t * substruct_sub_fl = NULL;
    void * any_elem = NULL;
    SV * sv_value = NULL;
    void * void_ptr = NULL;
    int64 poid_db = 0;
    int64 poid_id = 0;
    int64 poid_rev = 0;
    char * poid_type = NULL;
    char * poid_db_str = NULL;
    char * rec_id_str = NULL;
    int indexed_substruct = 0;
    int we_have_array_elements = 0;
    int we_have_substruct_elements = 0;
    
    ht = newHV(); 
    if(fl)
    {
        cookie = NULL;
        do
        {
            fld_num = 0;
            rec_id = -1;
            PIN_ERRBUF_RESET( & g_err_buffer);
            any_elem = PIN_FLIST_ANY_GET_NEXT(fl, & fld_num, & rec_id, & cookie, & g_err_buffer);
            if(PIN_ERRBUF_IS_ERR( & g_err_buffer)) break;
            if(fld_num) // Corrected: any_elem can be NULL, so we check fld_num
            {                   
                fld_name = (char *) pin_name_of_field(fld_num);
                fld_type = PIN_GET_TYPE_FROM_FLD(fld_num); 
                if(ppcm_is_indexed_simple_field(fl, fld_num, fld_type)) // Special case, different from array or substruct
                {
                    sub_ht = newHV();
                    cookie_2 = NULL;
                    do
                    {
                        rec_id_2 = -1;
                        PIN_ERRBUF_RESET( & g_err_buffer);
                        void_ptr = PIN_FLIST_ELEM_GET_NEXT(fl, fld_num, & rec_id_2, 0, & cookie_2, & g_err_buffer);
                        if(void_ptr)
                        {
                            rec_id_str = ppcm_int_to_str(rec_id_2);
                            ppcm_hv_store(sub_ht, rec_id_str, ppcm_ptr_to_sv(void_ptr, fld_type));
                            pin_free(rec_id_str);
                        };
                    }
                    while(void_ptr);
                    ppcm_hv_store(ht, fld_name, newRV( (SV *) sub_ht));
                }
                else
                {
                    switch(fld_type) 
                    {        
                        case PIN_FLDT_POID :
                        
                            if(PIN_POID_IS_NULL( (poid_t *) any_elem) && g_database != 0) // See: BRM manual
                            {
                                ppcm_hv_store(ht, fld_name, newRV(newSV(0)));                                                 
                            }
                            else
                            {
                                poid_db = PIN_POID_GET_DB( (poid_t *) any_elem);
                                poid_type = (char *) PIN_POID_GET_TYPE( (poid_t *) any_elem);
                                poid_id = PIN_POID_GET_ID( (poid_t *) any_elem);
                                poid_rev = PIN_POID_GET_REV( (poid_t *) any_elem);
                                poid_db_str = ppcm_poid_db_to_str(poid_db);
                                poid_ht = newHV();
                                // 23.07.2013 - Corrected (removed) references
                                sv_value = ppcm_newSVpv(poid_db_str); ppcm_hv_store(poid_ht, "db", sv_value);
                                sv_value = ppcm_newSVpv(poid_type); ppcm_hv_store(poid_ht, "type", sv_value);
                                sv_value = newSViv(poid_id); ppcm_hv_store(poid_ht, "id", sv_value);
                                sv_value = newSViv(poid_rev); ppcm_hv_store(poid_ht, "rev", sv_value);
                                ppcm_hv_store(ht, fld_name, newRV( (SV *) poid_ht));
                                pin_free(poid_db_str);
                            };
                            break;

                        case PIN_FLDT_ARRAY :
                        
                            sub_fl = (pin_flist_t *) any_elem;
                            if(sub_fl)
                            {
	                            sub_ht = newHV();
	                            cookie_2 = NULL;
	                            do
	                            {
	                                rec_id_2 = -1;
	                                PIN_ERRBUF_RESET( & g_err_buffer);
	                                array_sub_fl = PIN_FLIST_ELEM_GET_NEXT(fl, fld_num, & rec_id_2, 0, & cookie_2, & g_err_buffer);
	                                if(array_sub_fl)
	                                {
	                                    sub_ht_2 = ppcm_fl_to_ht(array_sub_fl);
	                                    rec_id_str = ppcm_int_to_str(rec_id_2);
	                                	we_have_array_elements = (hv_iterinit(sub_ht_2) > 0);
	                            		if(we_have_array_elements) // Corrected to avoid empty hashtables
	                                    {
	                                    	ppcm_hv_store(sub_ht, rec_id_str, newRV( (SV *) sub_ht_2));
	                                    }
	                                    else
	                                    {
	                                    	ppcm_hv_store(sub_ht, rec_id_str, newRV(newSV(0)));
	                                    };
	                                    pin_free(rec_id_str);
	                                };
	                            }
	                            while(array_sub_fl);
	                            ppcm_hv_store(ht, fld_name, newRV( (SV *) sub_ht));
                            }
                            else
                            {
	                            ppcm_hv_store(ht, fld_name, newRV(newSV(0)));
                            };
                            break;

                        case PIN_FLDT_SUBSTRUCT :

                            sub_fl = (pin_flist_t *) any_elem;
                            if(sub_fl)
                            {
	                            sub_ht = newHV();
	                            cookie_2 = NULL;
		                        rec_id_2 = -1;
		                        substruct_sub_fl = PIN_FLIST_ELEM_GET_NEXT(fl, fld_num, & rec_id_2, 0, & cookie_2, & g_err_buffer);
		                        indexed_substruct = (rec_id_2 > 0);	                        
		                        if(indexed_substruct)
	                            {
		                            cookie_2 = NULL;
		                            do
		                            {
		                                rec_id_2 = -1;
		                                PIN_ERRBUF_RESET( & g_err_buffer);
		                                substruct_sub_fl = PIN_FLIST_ELEM_GET_NEXT(fl, fld_num, & rec_id_2, 0, & cookie_2, & g_err_buffer);
		                                if(substruct_sub_fl)
		                                {
		                                    sub_ht_2 = ppcm_fl_to_ht(substruct_sub_fl);
		                                    rec_id_str = ppcm_int_to_str(rec_id_2);
		                                	we_have_substruct_elements = (hv_iterinit(sub_ht_2) > 0);
		                            		if(we_have_substruct_elements) // Corrected to avoid empty hashtables
		                                    {
		                                    	ppcm_hv_store(sub_ht, rec_id_str, newRV( (SV *) sub_ht_2));
		                                    }
		                                    else
		                                    {
		                                    	ppcm_hv_store(sub_ht, rec_id_str, newRV(newSV(0)));
		                                    };
		                                    pin_free(rec_id_str);
		                                };
		                            }
		                            while(substruct_sub_fl);
	                            }
	                            else
	                            {
	                            	sub_ht = ppcm_fl_to_ht(sub_fl);
	                            };
                            	ppcm_hv_store(ht, fld_name, newRV( (SV *) sub_ht));
                            }
                            else
                            {
	                            ppcm_hv_store(ht, fld_name, newRV(newSV(0)));
                            };
                            break;

                        case PIN_FLDT_OBJ :
                        case PIN_FLDT_TEXTBUF :
                        
                            ppcm_croak("%s: %s", ERR_MSG_CONVERSION_NOT_IMPLEMENTED, fld_name);
                            break;

                        default : // Simple element - ppcm_ptr_to_sv()
                        
                            ppcm_hv_store(ht, fld_name, ppcm_ptr_to_sv(any_elem, fld_type));        
                            break;
                    };
                };
            };
        }
        while(fld_num);
    };    
    return ht;
};

/*****************************************************************************************
 * 
 * 		Module body
 *
 ***************************************************************************************** 
 */
 
MODULE = Pcm                       PACKAGE = Pcm

PROTOTYPES: ENABLE

BOOT: 
        PIN_ERRBUF_CLEAR( & g_err_buffer);
        
        PCM_CONNECT( & g_ctxt, & g_database, & g_err_buffer);
        if(PIN_ERRBUF_IS_ERR( & g_err_buffer)) ppcm_croak(ERR_MSG_CONNECTION_FAILURE);
        
        pin_conf("ppcm", "logfile", PIN_FLDT_STR, & g_log_filename, & g_err_buffer);
        if(PIN_ERRBUF_IS_ERR( & g_err_buffer)) ppcm_croak(ERR_MSG_PIN_CONF_FAILED);
         
        pin_conf("ppcm", "loglevel", PIN_FLDT_INT, & g_log_level, & g_err_buffer);
        if(PIN_ERRBUF_IS_ERR( & g_err_buffer)) ppcm_croak(ERR_MSG_PIN_CONF_FAILED); 
		
		if(g_log_filename) PIN_ERR_SET_LOGFILE(g_log_filename); else PIN_ERR_SET_LOGFILE("debug.pinlog");
		if(g_log_level) PIN_ERR_SET_LOGLEVEL(*g_log_level); else PIN_ERR_SET_LOGLEVEL(3);
		PIN_ERR_SET_PROGRAM("Pcm");

void
hello()

    CODE:
    
        printf(PCM_HELLO_MSG, (int) g_database);
        
        XPUSHs(newRV( (SV *) newSViv(0)));

void
__collect_pcm_ops() // Returns hashtable of (opcode_name, opcode_index) tuples
        
void
op(opcode_0, flags, in_ht_0)
        SV * opcode_0; // Opcode name or integer const
        int flags;
        SV * in_ht_0;
        
    INIT:
    
        HV * in_ht = NULL;
        HV * out_ht = NULL;
        HV * eb_ht = NULL;
        SV * opcode_ref = NULL;
        pin_flist_t * in_fl = NULL;
        pin_flist_t * out_fl = NULL;
        int opcode_code = 0;
        
    PPCODE:
        
        // Input hashtable or string
        
        in_ht_ref = ppcm_deref(in_ht_0);
        if(SvTYPE(in_ht_ref) == SVt_PVHV)
        {
            in_fl = ppcm_ht_to_fl((HV *) in_ht_ref, NULL, NULL);
        }
        else if(SvTYPE(in_ht_ref) == SVt_PV || SvTYPE(in_ht_ref) == SVt_PVIV) && SvPOK(in_ht_ref))
        {
            PIN_STR_TO_FLIST(SvPV_nolen(in_ht_ref), g_database, & in_fl, & g_err_buffer);
            if(PIN_ERRBUF_IS_ERR( & g_err_buffer)) ppcm_croak(ERR_MSG_STR_TO_FLIST_FAILED);
        }
        else
        {
            ppcm_croak(ERR_MSG_INVALID_REFERENCE_TYPE);
        };     
        
        // Opocode name or number
        
        opcode_ref = ppcm_deref(opcode_0);
    	if(SvTYPE(opcode_ref) == SVt_PV && SvPOK(opcode_ref))
    	{
    		opcode_code = pcm_opname_to_opcode(SvPV_nolen(opcode_ref));
    	}
    	else if((SvTYPE(opcode_ref) == SVt_IV || SvTYPE(opcode_ref) == SVt_PVIV) && SvIOK(opcode_ref))
    	{
    		opcode_code = SvIV(opcode_ref);
    	}
    	else
    	{
            ppcm_croak(ERR_MSG_INVALID_REFERENCE_TYPE);
    	};
        
        // Execution
        
        if(opcode_code > 0)
        {
            PIN_ERR_LOG_FLIST(g_log_level, "Pcm::op -> input flist:", in_fl);
            if( ! in_fl)
            {
                ppcm_croak(ERR_MSG_CONVERSION_OF_HT_FAILED);
            }
            else
            {
                PIN_ERRBUF_RESET( & g_err_buffer);
                out_fl = NULL;
                
                PCM_OP(g_ctxt, opcode_code, flags, in_fl, & out_fl, & g_err_buffer);
                // TODO: PCM_OPREF() maybe ?
                
                if( ! out_fl && g_err_buffer.pin_err == 0) ppcm_croak(ERR_MSG_NULL_OUT_FL);
                eb_ht = ppcm_eb_to_ht( & g_err_buffer);
            	PIN_ERR_LOG_FLIST(g_log_level, "Pcm::op -> output flist:", in_fl);
                out_ht = ppcm_fl_to_ht(out_fl);
                PIN_ERRBUF_RESET( & g_err_buffer); // To clean after PCM_OP
                PIN_FLIST_DESTROY_EX( & in_fl, & g_err_buffer);
                if(PIN_ERRBUF_IS_ERR( & g_err_buffer)) ppcm_croak(ERR_MSG_UNABLE_TO_FREE_FLIST);
                PIN_FLIST_DESTROY_EX( & out_fl, & g_err_buffer);
                if(PIN_ERRBUF_IS_ERR( & g_err_buffer)) ppcm_croak(ERR_MSG_UNABLE_TO_FREE_FLIST);
            };
        }
        else
        {
            ppcm_croak("%s: %s", ERR_MSG_INVALID_OPCODE, opcode);
        };
        
        XPUSHs(newRV(sv_2mortal( (SV *) out_ht)));
        XPUSHs(newRV(sv_2mortal( (SV *) eb_ht)));

=head1 NAME

Pcm - Perl XS module performing BRM PCM_OP via hashtables: 

    ($out, $ebuf) = Pcm::op($opcode, $in, $flags)

=head1 SYNOPSIS

B<Real-life example>:

    use ExtUtils::testlib;
    use Data::Dumper;
    use Pcm;
    
    $opcode = "PCM_OP_SEARCH";
    $flags = 0;
    $in =>
        {
            "PIN_FLD_POID" => 
                {
                    "db" => "0.0.0.1",
                    "type" => "/search",
                    "id" => -1,
                    "rev" => 0
                },
            "PIN_FLD_FLAGS" => 0,
            "PIN_FLD_TEMPLATE" => "select X from /event/billing/payment/ where F1 like V1 ",
            "PIN_FLD_ARGS" =>
                {
                    1 =>
                    {
                        "PIN_FLD_POID" =>
                            {
                                "db" => "0.0.0.1",
                                "type" => "/event/billing/payment/",
                                "id" => -1,
                                "rev" => 0
                            }
                    }
                },
            "PIN_FLD_RESULTS" => 
                {
                    "100" => undef
                }
        };
    
    ($out, $ebuf) = Pcm::op($opcode, $flags, $in);
    
    print Dumper($in);
    print Dumper($out);

=head1 DESCRIPTION

=over 12

=item * At the boot time module connects with BRM database according to pin.conf settings in local directory.

=item * Module depends of -lportal and -lpcmext or their 64-bit counterparts.

=item * We use only PIN memory management (pin_malloc(), pin_free() and pin_strdup()).

=item * We allow indices for both array and substruct fields and also simple fields.

=item * Input and output flists apart from being converted to hashtable are also written to DEBUG_IN_FL_FILE and DEBUG_OUT_FL_FILE.

=item * Module checks types.

=item * NULL decimals, timestamps, POIDs and strings are converted to (undef) instead of 0 and "".

=item * Conversion of PIN_FLDT_OBJ and PIN_FLDT_TEXTBUF is not implemented.

=back

=head2 EXPORTED PERL FUNCTIONS:

=head3 ($out, $ebuf) = op($opcode, $flags, $in)

    $opcode - integer or string representation of opcode
    $flags - integer flags value
    $in - input flist as hashtable
    $out - output flist converted to hashtable
    $ebuf - error buffer converted to hashtable

=head2 ERROR MESSAGES:

=head3 [failed to connect]

        The module was unable to connect to BRM database according to pin.conf configuration.

=head3 [invalid opcode]

        Attempt to execute unknown opcode.

=head3 [invalid size of POID hashtable]

        The POID hashtable has to have 3 or 4 entries.

=head3 [invalid POID hashtable structure]

        The POID hashtable must consist of "id", "db", "type" and optional "rev" entry.

=head3 [invalid type in POID hashtable]

        Only integers and strings are allowed.

=head3 [invalid reference type]

        F.e. Perl array is not allowed in input hashtable.

=head3 [invalid reference]

=head3 [invalid entry key]

        We allow only integers or valid PIN fields.        

=head3 [invalid field type]

=head3 [invalid array hashtable structure]

        Detected non-indexed element in array hashtable.

=head3 [invalid substruct hashtable structure]

        F.e. simple value instead of hashtable or indexed hashtable.

=head3 [array element in substructure]

=head3 [conflicting type]

        Conflict of Perl type with PIN type of destination field.

=head3 [substruct in array]

=head3 [no index for array element]
        
        Lack of index in the array hashtable entry

=head3 [no index for indexed normal field]

        Lack of index in the indexed simple field array entry

=head3 [no index for indexed substruct element]

        Lack of index in the indexed substructure array entry

=head3 [unable to create POID]

=head3 [failed to allocate flist]

=head3 [unable to free flist]

=head3 [conversion of hashtable failed]

=head3 [conversion of unknown PIN type]

=head3 [conversion of PIN_FLDT_OBJ, PIN_FLDT_TEXTBUF not implemented]

=head3 [conversion of obsolete type PIN_FLDT_NUM]

        Conversion of PIN_FLDT_NUM type of field is locked.

=head3 [negative index in array]

=head3 [NULL flist pointer]

=head3 [NULL hashtable pointer]

=head3 [NULL error buffer pointer]

=head3 [NULL output flist pointer]

=head2 INTERNAL C FUNCTIONS:

=head3 struct he_data

Helper structure consisting of decomposed HE (hash entry) data.
Used throughout module to simplify passing parameters of HE.

    char * key_str; - string value of key of the hash entry
    SV * value; - SV pointer to the value of the hash entry
    svtype type; - type of the value
    int is_hashtable; - helper flag
    int is_indexed_simple_field; - helper flag
    pin_fld_num_t pin_num; - PIN num of the field
    pin_fld_type_t pin_type; - PIN type of the field
    int pin_is_complex_type; - array or substruct ?
    int we_have_index; - is the key_str integer
    int index; - integer value of the key_str

=head3 pin_flist_t * ppcm_ht_to_fl(HV * ht, pin_flist_t * parent_fl, he_data_t * parent_he_data);

Main function converting hashtable to BRM flist.

    HV * ht - hashtable to convert
    pin_flist_t * parent_fl - parent flist to attach elements to
    he_data_t * parent_he_data - data of parent flist hash entry

    Returns pin_flist_t * - converted flist

=head3 void ppcm_ht_to_fl_elems(HV * ht, pin_flist_t * parent_fl, he_data_t * parent_he_data, int indexed_simple_field);

Helper function iterating trough elements of hashtable, and adding them to the parent flist.
Called from ppcm_ht_to_fl().

    HV * ht - hashtable we iterate through
    pin_flist_t * parent_fl - parent flist to attach elements to
    he_data_t * parent_he_data - data of parent flist hash entry
    int indexed_simple_field - does parent hashtable is attached to indexed simple field ?

=head3 void ppcm_ht_to_fl_elem(HE * he, pin_flist_t * parent_fl, he_data_t * parent_he_data, int indexed_simple_field);

Helper function converting hash entry to flist element, and adding it to the parent flist.
Called from ppcm_ht_to_fl() or ppcm_ht_to_fl_elems().

    HE * he - hash entry to convert
    pin_flist_t * parent_fl - parent flist to attach element to
    he_data_t * parent_he_data - data of parent flist hash entry
    int indexed_simple_field - does parent hashtable is attached to indexed simple field ?

=head3 poid_t * ppcm_ht_to_fl_poid(HV * ht);

Function converting POID hash table to POID.

    HV * ht - POID hashtable to construct POID from

=head3 HV * ppcm_eb_to_ht(pin_errbuf_t * eb);

Function converting error buffer to hashtable.

    pin_errbuf_t * eb - error buffer to convert

=head3 HV * ppcm_fl_to_ht(pin_flist_t * fl);

Function converting flist to hashtable.
    
    pin_flist_t * fl - flist to convert

=head3 SV * ppcm_ptr_to_sv(void * p, pin_fld_type_t fld_type);

Function converting flist simple element value to SV Perl value according to fld_type.

    void * p - pointer to the value
    pin_fld_type_t fld_type - PIN type of value

=head3 void ppcm_decompose_ht_entry(HE * he, he_data_t * he_data);

Function decomposing hash entry to the he_data structure.

    HE * he - hash entry to decompose 
    he_data_t * he_data - structure holding decomposed data

=head3 void ppcm_check_type(he_data_t * he_data, pin_fld_type_t type);

Function checking type consistency of he_data structure.

    he_data_t * he_data - decomposed hash entry data
    pin_fld_type_t type - PIN type to check with

=head3 char * ppcm_pin_type_to_str(pin_fld_type_t type);

Function converting PIN type to string.

=head3 char * ppcm_perl_type_to_str(svtype type);

Function converting Perl type to string.

=head3 static inline char * ppcm_poid_db_to_str(int64 db);

Function converting POID database ID to string.

=head3 static inline char * ppcm_int_to_str(int n);

Function converting integer value to string.

=head3 static inline SV * ppcm_newRVnewSVpv(char * s);

Function creating new SV value from string.

=head3 void ppcm_croak(const char * msg, ...);

Function to croak printf()-way.

=head1 CAVEATS 

=over 12

=item * Conversion of PIN_FLDT_OBJ and PIN_FLDT_TEXTBUF flist entities is not implemented and leads to error.

=item * PIN_FLDT_NUM is treated as obsolete type and leads to error.

=back

=head1 BUGS

This is beta version. Please report bugs to the author.

=head1 SEE ALSO

=over 12

=item * Understanding Flists and Storable Classes: (L<http://docs.oracle.com/cd/E16754_01/doc.75/e16702/prg_intro_data_struct.htm#i445692>)

=item * Understanding the BRM Data Types: (L<http://docs.oracle.com/cd/E16754_01/doc.75/e16702/prg_data_types.htm>)

=item * Opcode Reference: (L<http://docs.oracle.com/cd/E16754_01/doc.75/e16714/ref_pcm_opcodes.htm>)

=back

=head1 AUTHOR

Tomasz Budzeñ, Accenture (L<mailto://tomasz.budzen@accenture.com>)

=cut
