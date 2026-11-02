// Darwin entry points for libxml2's variadic and va_list functions, made
// with perry_wrapped.h's VARIADIC and VA_LIST.

#include "perry_wrapped.h"

#if defined(__aarch64__) && defined(__ELF__)

.text

// MARK: - xmlstring.h

VARIADIC _xmlStrPrintf, xmlStrVPrintf, 3
VA_LIST _xmlStrVPrintf, xmlStrVPrintf, 3

// MARK: - xmlerror.h
// These have no va_list forms in libxml2; provider.c formats the message
// and reports it.

VARIADIC _xmlParserError, perry_xml_parser_error_v, 2
VARIADIC _xmlParserWarning, perry_xml_parser_warning_v, 2
VARIADIC _xmlParserValidityError, perry_xml_parser_validity_error_v, 2
VARIADIC _xmlParserValidityWarning, perry_xml_parser_validity_warning_v, 2

// The handler ___xmlGenericError hands Darwin code for a native one:
// provider.c formats the message and calls the native handler.
VARIADIC perry_xml_generic_error_darwin, perry_xml_generic_error_v, 2
    .hidden perry_xml_generic_error_darwin

// MARK: - xmlwriter.h

VARIADIC _xmlTextWriterWriteFormatComment, xmlTextWriterWriteVFormatComment, 2
VA_LIST _xmlTextWriterWriteVFormatComment, xmlTextWriterWriteVFormatComment, 2
VARIADIC _xmlTextWriterWriteFormatString, xmlTextWriterWriteVFormatString, 2
VA_LIST _xmlTextWriterWriteVFormatString, xmlTextWriterWriteVFormatString, 2
VARIADIC _xmlTextWriterWriteFormatRaw, xmlTextWriterWriteVFormatRaw, 2
VA_LIST _xmlTextWriterWriteVFormatRaw, xmlTextWriterWriteVFormatRaw, 2
VARIADIC _xmlTextWriterWriteFormatCDATA, xmlTextWriterWriteVFormatCDATA, 2
VA_LIST _xmlTextWriterWriteVFormatCDATA, xmlTextWriterWriteVFormatCDATA, 2
VARIADIC _xmlTextWriterWriteFormatElement, xmlTextWriterWriteVFormatElement, 3
VA_LIST _xmlTextWriterWriteVFormatElement, xmlTextWriterWriteVFormatElement, 3
VARIADIC _xmlTextWriterWriteFormatAttribute, xmlTextWriterWriteVFormatAttribute, 3
VA_LIST _xmlTextWriterWriteVFormatAttribute, xmlTextWriterWriteVFormatAttribute, 3
VARIADIC _xmlTextWriterWriteFormatPI, xmlTextWriterWriteVFormatPI, 3
VA_LIST _xmlTextWriterWriteVFormatPI, xmlTextWriterWriteVFormatPI, 3
VARIADIC _xmlTextWriterWriteFormatDTDElement, xmlTextWriterWriteVFormatDTDElement, 3
VA_LIST _xmlTextWriterWriteVFormatDTDElement, xmlTextWriterWriteVFormatDTDElement, 3
VARIADIC _xmlTextWriterWriteFormatDTDAttlist, xmlTextWriterWriteVFormatDTDAttlist, 3
VA_LIST _xmlTextWriterWriteVFormatDTDAttlist, xmlTextWriterWriteVFormatDTDAttlist, 3
VARIADIC _xmlTextWriterWriteFormatDTDInternalEntity, xmlTextWriterWriteVFormatDTDInternalEntity, 4
VA_LIST _xmlTextWriterWriteVFormatDTDInternalEntity, xmlTextWriterWriteVFormatDTDInternalEntity, 4
VARIADIC _xmlTextWriterWriteFormatElementNS, xmlTextWriterWriteVFormatElementNS, 5
VA_LIST _xmlTextWriterWriteVFormatElementNS, xmlTextWriterWriteVFormatElementNS, 5
VARIADIC _xmlTextWriterWriteFormatAttributeNS, xmlTextWriterWriteVFormatAttributeNS, 5
VA_LIST _xmlTextWriterWriteVFormatAttributeNS, xmlTextWriterWriteVFormatAttributeNS, 5
VARIADIC _xmlTextWriterWriteFormatDTD, xmlTextWriterWriteVFormatDTD, 5
VA_LIST _xmlTextWriterWriteVFormatDTD, xmlTextWriterWriteVFormatDTD, 5

// MARK: - Calling Darwin's variadic handlers

// perry_xml_call_darwin_variadic(function, context, format, argument)
//
// Calls a Darwin handler f(void *ctx, const char *msg, ...) with one
// variadic argument, which Darwin's ABI expects on the stack.
    .globl perry_xml_call_darwin_variadic
    .hidden perry_xml_call_darwin_variadic
    .type perry_xml_call_darwin_variadic, %function
    .p2align 2
perry_xml_call_darwin_variadic:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    sub sp, sp, #16
    str x3, [sp]                // the variadic argument, at the callee's sp
    mov x16, x0
    mov x0, x1
    mov x1, x2
    blr x16
    mov sp, x29
    ldp x29, x30, [sp], #16
    ret
    .size perry_xml_call_darwin_variadic, . - perry_xml_call_darwin_variadic

#endif

.section .note.GNU-stack, "", %progbits
