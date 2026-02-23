################################################################################
#
# python-pikepdf
#
################################################################################

PYTHON_PIKEPDF_VERSION = 9.4.2
PYTHON_PIKEPDF_SOURCE = pikepdf-9.4.2.tar.gz
PYTHON_PIKEPDF_SITE = https://files.pythonhosted.org/packages/57/54/71552c3ab2694618741e5579506759238716664400304cb615917a993df5
PYTHON_PIKEPDF_SETUP_TYPE = setuptools
PYTHON_PIKEPDF_LICENSE = UNKNOWN
PYTHON_PIKEPDF_DEPENDENCIES = host-python-pip qpdf
PYTHON_PIKEPDF_PYBIND11_VERSION = 2.13.6
PYTHON_PIKEPDF_ENV = \
	CPATH="$(STAGING_DIR)/usr/include" \
	LIBRARY_PATH="$(STAGING_DIR)/usr/lib" \
	CFLAGS="$(TARGET_CFLAGS) -I$(STAGING_DIR)/usr/include" \
	CXXFLAGS="$(TARGET_CXXFLAGS) -I$(STAGING_DIR)/usr/include" \
	LDFLAGS="$(TARGET_LDFLAGS) -L$(STAGING_DIR)/usr/lib -Wl,-rpath-link,$(STAGING_DIR)/usr/lib"

define PYTHON_PIKEPDF_INSTALL_PYBIND11
	rm -rf $(@D)/.pybind11-wheelhouse
	mkdir -p $(@D)/.pybind11-wheelhouse
	PIP_DISABLE_PIP_VERSION_CHECK=1 \
	PIP_NO_CACHE_DIR=1 \
	python3 -m pip download --only-binary=:all: --dest $(@D)/.pybind11-wheelhouse \
		pybind11==$(PYTHON_PIKEPDF_PYBIND11_VERSION)
	PIP_DISABLE_PIP_VERSION_CHECK=1 \
	PIP_NO_CACHE_DIR=1 \
	$(HOST_DIR)/bin/python3 -m pip install --no-index --find-links $(@D)/.pybind11-wheelhouse \
		pybind11==$(PYTHON_PIKEPDF_PYBIND11_VERSION)
	rm -rf $(@D)/.pybind11-wheelhouse
endef
PYTHON_PIKEPDF_PRE_BUILD_HOOKS += PYTHON_PIKEPDF_INSTALL_PYBIND11

$(eval $(python-package))
