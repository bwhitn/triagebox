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

define PYTHON_LIEF_INSTALL_BUILD_REQUIREMENTS
	PIP_DISABLE_PIP_VERSION_CHECK=1 \
	PIP_NO_CACHE_DIR=1 \
	$(HOST_DIR)/bin/python3 -m pip install --no-cache-dir \
		-r $(@D)/api/python/build-requirements.txt
endef
PYTHON_LIEF_PRE_BUILD_HOOKS += PYTHON_LIEF_INSTALL_BUILD_REQUIREMENTS

$(eval $(python-package))
