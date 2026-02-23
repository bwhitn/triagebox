################################################################################
#
# python-evtx
#
################################################################################

PYTHON_EVTX_VERSION = 0.8.1
PYTHON_EVTX_SOURCE = python_evtx-0.8.1.tar.gz
PYTHON_EVTX_SITE = https://files.pythonhosted.org/packages/34/44/e28f31531834b1cd93d14472ec84136dad565e9db0f7abcbae96176c1e65
PYTHON_EVTX_SETUP_TYPE = setuptools
PYTHON_EVTX_LICENSE = UNKNOWN

define PYTHON_EVTX_FIX_ENTRYPOINTS
	if [ -f $(TARGET_DIR)/usr/bin/evtx_dump ]; then \
		$(SED) 's|from scripts.evtx_dump import main|from Evtx.scripts.evtx_dump import main|g' $(TARGET_DIR)/usr/bin/evtx_dump; \
	fi
	if [ -f $(TARGET_DIR)/usr/bin/evtx_dump_json ]; then \
		$(SED) 's|from scripts.evtx_dump_json import main|from Evtx.scripts.evtx_dump_json import main|g' $(TARGET_DIR)/usr/bin/evtx_dump_json; \
	fi
	if [ -f $(TARGET_DIR)/usr/bin/evtx_info ]; then \
		$(SED) 's|from scripts.evtx_info import main|from Evtx.scripts.evtx_info import main|g' $(TARGET_DIR)/usr/bin/evtx_info; \
	fi
	if [ -f $(TARGET_DIR)/usr/bin/evtx_templates ]; then \
		$(SED) 's|from scripts.evtx_templates import main|from Evtx.scripts.evtx_templates import main|g' $(TARGET_DIR)/usr/bin/evtx_templates; \
	fi
endef
PYTHON_EVTX_POST_INSTALL_TARGET_HOOKS += PYTHON_EVTX_FIX_ENTRYPOINTS

$(eval $(python-package))
