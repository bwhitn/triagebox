################################################################################
#
# python-oletools
#
################################################################################

PYTHON_OLETOOLS_VERSION = 0.60.2
PYTHON_OLETOOLS_SOURCE = oletools-$(PYTHON_OLETOOLS_VERSION).zip
PYTHON_OLETOOLS_SITE = https://files.pythonhosted.org/packages/5c/2f/037f40e44706d542b94a2312ccc33ee2701ebfc9a83b46b55263d49ce55a
PYTHON_OLETOOLS_SETUP_TYPE = setuptools
PYTHON_OLETOOLS_LICENSE = BSD
PYTHON_OLETOOLS_DEPENDENCIES = python-pyparsing

define PYTHON_OLETOOLS_EXTRACT_CMDS
	$(UNZIP) -d $(@D) $(PYTHON_OLETOOLS_DL_DIR)/$(PYTHON_OLETOOLS_SOURCE)
	mv $(@D)/oletools-$(PYTHON_OLETOOLS_VERSION)/* $(@D)
	$(RM) -r $(@D)/oletools-$(PYTHON_OLETOOLS_VERSION)
endef

# ezhexviewer is GUI-only and requires tkinter/X11, which are intentionally
# not part of this headless target image.
define PYTHON_OLETOOLS_REMOVE_GUI_ENTRYPOINT
	rm -f $(TARGET_DIR)/usr/bin/ezhexviewer
endef
PYTHON_OLETOOLS_POST_INSTALL_TARGET_HOOKS += PYTHON_OLETOOLS_REMOVE_GUI_ENTRYPOINT

$(eval $(python-package))
