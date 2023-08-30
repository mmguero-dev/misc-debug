spicy_add_analyzer(
    NAME ASN
    PACKAGE_NAME spicy-asn
    SOURCES asn.spicy asn1.spicy asn.evt zeek_asn.spicy
    SCRIPTS __load__.zeek main.zeek dpd.sig
)
