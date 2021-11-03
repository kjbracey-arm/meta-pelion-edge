require maestro_0.0.2.inc

COMPATIBLE_MACHINE = "uz"

PROVIDES += " maestro "
RPROVIDES_${PN} += " maestro "

FILESEXTRAPATHS_prepend := "${THISDIR}/maestro/uz:"
SRC_URI += "file://maestro-config-uz.yaml \
            file://devicedb.template.conf \
            file://relayTerm.template.json \
            "

do_install_append() {
    # Maestro configuration management
    install -d ${D}/${RUN_CONFIG_DIR}
    install -d ${D}/${TEMPLATE_CONFIG_DIR}
    install -m 0644 ${WORKDIR}/maestro-config-uz.yaml ${D}/${RUN_CONFIG_DIR}/maestro-config.yaml
    install -m 0644 ${WORKDIR}/devicedb.template.conf ${D}/${TEMPLATE_CONFIG_DIR}/devicedb.template.conf
    install -m 0644 ${WORKDIR}/relayTerm.template.json ${D}/${TEMPLATE_CONFIG_DIR}/relayTerm.template.json
}
