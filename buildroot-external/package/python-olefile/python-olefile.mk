################################################################################
#
# python-olefile
#
################################################################################

PYTHON_OLEFILE_VERSION = 0.47.dev4
PYTHON_OLEFILE_SOURCE = olefile-0.47.dev4.zip
PYTHON_OLEFILE_SITE = https://files.pythonhosted.org/packages/ff/47/a56c2812bc96dd4e33aba3acac0e2d9c78d9ef768d6654a84a343647c7f1
PYTHON_OLEFILE_SETUP_TYPE = setuptools
PYTHON_OLEFILE_LICENSE = BSD

define PYTHON_OLEFILE_EXTRACT_CMDS
	$(UNZIP) -d $(@D) $(PYTHON_OLEFILE_DL_DIR)/$(PYTHON_OLEFILE_SOURCE)
	mv $(@D)/olefile-$(PYTHON_OLEFILE_VERSION)/* $(@D)
	$(RM) -r $(@D)/olefile-$(PYTHON_OLEFILE_VERSION)
endef

$(eval $(python-package))
