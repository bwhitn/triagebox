################################################################################
#
# python-oletools
#
################################################################################

PYTHON_OLETOOLS_VERSION = 0.08a
PYTHON_OLETOOLS_SOURCE = oletools-0.08a.zip
PYTHON_OLETOOLS_SITE = https://files.pythonhosted.org/packages/0b/e1/48780f5675e80f368304b118cab460196cc8df26ea1097c461de0b5a213c
PYTHON_OLETOOLS_SETUP_TYPE = setuptools
PYTHON_OLETOOLS_LICENSE = BSD

define PYTHON_OLETOOLS_EXTRACT_CMDS
	$(UNZIP) -d $(@D) $(PYTHON_OLETOOLS_DL_DIR)/$(PYTHON_OLETOOLS_SOURCE)
	mv $(@D)/oletools-$(PYTHON_OLETOOLS_VERSION)/* $(@D)
	$(RM) -r $(@D)/oletools-$(PYTHON_OLETOOLS_VERSION)
endef

$(eval $(python-package))
