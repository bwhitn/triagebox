################################################################################
#
# python-hexdump
#
################################################################################

PYTHON_HEXDUMP_VERSION = 3.3
PYTHON_HEXDUMP_SOURCE = hexdump-3.3.zip
PYTHON_HEXDUMP_SITE = https://files.pythonhosted.org/packages/55/b3/279b1d57fa3681725d0db8820405cdcb4e62a9239c205e4ceac4391c78e4
PYTHON_HEXDUMP_SETUP_TYPE = setuptools
PYTHON_HEXDUMP_LICENSE = Public Domain

define PYTHON_HEXDUMP_EXTRACT_CMDS
	$(UNZIP) -d $(@D) $(PYTHON_HEXDUMP_DL_DIR)/$(PYTHON_HEXDUMP_SOURCE)
endef

$(eval $(python-package))
