################################################################################
#
# python-backports-lzma
#
################################################################################

PYTHON_BACKPORTS_LZMA_VERSION = 0.0.14
PYTHON_BACKPORTS_LZMA_SOURCE = backports.lzma-$(PYTHON_BACKPORTS_LZMA_VERSION).tar.gz
PYTHON_BACKPORTS_LZMA_SITE = https://files.pythonhosted.org/packages/source/b/backports.lzma
PYTHON_BACKPORTS_LZMA_SETUP_TYPE = setuptools
PYTHON_BACKPORTS_LZMA_LICENSE = Python-2.0
PYTHON_BACKPORTS_LZMA_DEPENDENCIES = xz

define PYTHON_BACKPORTS_LZMA_SANITIZE_SETUP
	if [ -f $(@D)/setup.py ]; then \
		for path in /usr/local/include /opt/local/include /usr/local/lib /opt/local/lib; do \
			$(SED) "s|'$$path', *||g" $(@D)/setup.py; \
			$(SED) "s|, *'$$path'||g" $(@D)/setup.py; \
			$(SED) "s|\"$$path\", *||g" $(@D)/setup.py; \
			$(SED) "s|, *\"$$path\"||g" $(@D)/setup.py; \
		done; \
		for kind in include lib; do \
			$(SED) "s|os.path.expanduser('~/$$kind'), *||g" $(@D)/setup.py; \
			$(SED) "s|, *os.path.expanduser('~/$$kind')||g" $(@D)/setup.py; \
			$(SED) "s|os.path.expanduser(\"~/$$kind\"), *||g" $(@D)/setup.py; \
			$(SED) "s|, *os.path.expanduser(\"~/$$kind\")||g" $(@D)/setup.py; \
		done; \
	fi
endef
PYTHON_BACKPORTS_LZMA_POST_PATCH_HOOKS += PYTHON_BACKPORTS_LZMA_SANITIZE_SETUP
PYTHON_BACKPORTS_LZMA_PRE_BUILD_HOOKS += PYTHON_BACKPORTS_LZMA_SANITIZE_SETUP

define PYTHON_BACKPORTS_LZMA_EXTRACT_CMDS
	$(INFLATE$(suffix $(PYTHON_BACKPORTS_LZMA_SOURCE))) $(PYTHON_BACKPORTS_LZMA_DL_DIR)/$(PYTHON_BACKPORTS_LZMA_SOURCE) | \
	$(TAR) --no-same-owner --strip-components=$(PYTHON_BACKPORTS_LZMA_STRIP_COMPONENTS) \
		-C $(@D) \
		$(foreach x,$(PYTHON_BACKPORTS_LZMA_EXCLUDES),--exclude='$(x)' ) \
		$(TAR_OPTIONS) -
endef

$(eval $(python-package))
