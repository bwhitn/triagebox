################################################################################
#
# python-lief
#
################################################################################

PYTHON_LIEF_VERSION = 0.17.3
PYTHON_LIEF_SITE = $(call github,lief-project,LIEF,$(PYTHON_LIEF_VERSION))
PYTHON_LIEF_SUBDIR = api/python
PYTHON_LIEF_SETUP_TYPE = pep517
PYTHON_LIEF_LICENSE = Apache License 2.0
PYTHON_LIEF_DEPENDENCIES = host-cmake host-ninja host-python-pip

define PYTHON_LIEF_FIX_PYCONFIG_HEADER
	mkdir -p $(PYTHON3_DIR)/Include
	if [ ! -f $(PYTHON3_DIR)/Include/pyconfig.h ]; then \
		if [ -f $(PYTHON3_DIR)/pyconfig.h ]; then \
			ln -sf ../pyconfig.h $(PYTHON3_DIR)/Include/pyconfig.h; \
		elif [ -f $(STAGING_DIR)/usr/include/python$(PYTHON3_VERSION_MAJOR)/pyconfig.h ]; then \
			ln -sf $(STAGING_DIR)/usr/include/python$(PYTHON3_VERSION_MAJOR)/pyconfig.h \
				$(PYTHON3_DIR)/Include/pyconfig.h; \
		fi; \
	fi
endef
PYTHON_LIEF_PRE_BUILD_HOOKS += PYTHON_LIEF_FIX_PYCONFIG_HEADER

define PYTHON_LIEF_ADJUST_BUILD_REQUIREMENTS
	if [ -f $(@D)/api/python/build-requirements.txt ]; then \
		$(SED) -i -e 's/^pydantic==2\.11\.3$$/pydantic>=2.11.3,<3/' \
			$(@D)/api/python/build-requirements.txt; \
	fi
endef
PYTHON_LIEF_PRE_BUILD_HOOKS += PYTHON_LIEF_ADJUST_BUILD_REQUIREMENTS

define PYTHON_LIEF_INSTALL_BUILD_REQUIREMENTS
	rm -rf $(@D)/.lief-wheelhouse
	mkdir -p $(@D)/.lief-wheelhouse
	PIP_DISABLE_PIP_VERSION_CHECK=1 \
	PIP_NO_CACHE_DIR=1 \
	$(HOST_DIR)/bin/python3 -m pip download --only-binary=:all: --dest $(@D)/.lief-wheelhouse \
		-r $(@D)/api/python/build-requirements.txt
	PIP_DISABLE_PIP_VERSION_CHECK=1 \
	PIP_NO_CACHE_DIR=1 \
	$(HOST_DIR)/bin/python3 -m pip install --no-index --find-links $(@D)/.lief-wheelhouse \
		-r $(@D)/api/python/build-requirements.txt
	rm -rf $(@D)/.lief-wheelhouse
endef
PYTHON_LIEF_PRE_BUILD_HOOKS += PYTHON_LIEF_INSTALL_BUILD_REQUIREMENTS

$(eval $(python-package))
