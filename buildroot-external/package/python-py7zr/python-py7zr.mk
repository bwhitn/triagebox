################################################################################
#
# python-py7zr
#
################################################################################

PYTHON_PY7ZR_VERSION = 1.1.0rc4
PYTHON_PY7ZR_SOURCE = py7zr-1.1.0rc4.tar.gz
PYTHON_PY7ZR_SITE = https://files.pythonhosted.org/packages/a1/99/0acbe1ef4c4f1a09fd5f96f2c24f77179c2b2e566686d2ac80646a4603ff
PYTHON_PY7ZR_SETUP_TYPE = setuptools
PYTHON_PY7ZR_LICENSE = UNKNOWN
PYTHON_PY7ZR_DEPENDENCIES = host-python-setuptools-scm host-python-pip \
	python-inflate64 python-multivolumefile python-pybcj python-pyzstd

define PYTHON_PY7ZR_FIX_PYPROJECT_LICENSE
	$(SED) 's|^license = "LGPL-2.1-or-later"$$|license = { text = "LGPL-2.1-or-later" }|g' \
		$(@D)/pyproject.toml
endef
PYTHON_PY7ZR_POST_PATCH_HOOKS += PYTHON_PY7ZR_FIX_PYPROJECT_LICENSE

define PYTHON_PY7ZR_RELAX_BUILD_BACKEND_REQS
	if [ -f $(@D)/pyproject.toml ]; then \
		$(SED) 's|setuptools>=80|setuptools|g' $(@D)/pyproject.toml; \
		$(SED) 's|setuptools_scm\\[toml\\]>=9.2.0|setuptools_scm[toml]|g' $(@D)/pyproject.toml; \
	fi
	if [ -f $(@D)/setup.py ]; then \
		$(SED) 's|setuptools_scm\\[toml\\]>=9.2.0|setuptools_scm[toml]|g' $(@D)/setup.py; \
	fi
	if [ -f $(@D)/setup.cfg ]; then \
		$(SED) 's|setuptools_scm\\[toml\\]>=9.2.0|setuptools_scm[toml]|g' $(@D)/setup.cfg; \
	fi
endef
PYTHON_PY7ZR_POST_PATCH_HOOKS += PYTHON_PY7ZR_RELAX_BUILD_BACKEND_REQS

define PYTHON_PY7ZR_FORCE_STDLIB_LZMA
	set -e; \
	for compressor_py in $$(find $(@D) -type f -path '*/py7zr/compressor.py'); do \
		$(SED) 's|from backports import lzma as lzma|import lzma|g' "$$compressor_py"; \
		$(SED) 's|from backports import lzma|import lzma|g' "$$compressor_py"; \
		$(SED) 's|import backports\\.lzma as lzma|import lzma|g' "$$compressor_py"; \
		$(SED) 's|from backports\\.lzma import |from lzma import |g' "$$compressor_py"; \
		$(SED) 's|backports\\.lzma|lzma|g' "$$compressor_py"; \
		$(SED) 's|from backports import zstd|import pyzstd as zstd|g' "$$compressor_py"; \
	done
endef
PYTHON_PY7ZR_POST_PATCH_HOOKS += PYTHON_PY7ZR_FORCE_STDLIB_LZMA

define PYTHON_PY7ZR_INSTALL_BUILD_BACKEND_DEPS
	rm -rf $(@D)/.py7zr-wheelhouse
	mkdir -p $(@D)/.py7zr-wheelhouse
	PIP_DISABLE_PIP_VERSION_CHECK=1 \
	PIP_NO_CACHE_DIR=1 \
	$(HOST_DIR)/bin/python3 -m pip download --only-binary=:all: --dest $(@D)/.py7zr-wheelhouse \
		"setuptools>=80" "setuptools_scm[toml]>=9.2.0"
	PIP_DISABLE_PIP_VERSION_CHECK=1 \
	PIP_NO_CACHE_DIR=1 \
	$(HOST_DIR)/bin/python3 -m pip install --no-index --find-links $(@D)/.py7zr-wheelhouse \
		"setuptools>=80" "setuptools_scm[toml]>=9.2.0"
	rm -rf $(@D)/.py7zr-wheelhouse
endef
PYTHON_PY7ZR_PRE_BUILD_HOOKS += PYTHON_PY7ZR_INSTALL_BUILD_BACKEND_DEPS

$(eval $(python-package))
