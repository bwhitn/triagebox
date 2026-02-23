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
PYTHON_PY7ZR_DEPENDENCIES = host-python-setuptools-scm

define PYTHON_PY7ZR_FIX_PYPROJECT_LICENSE
	$(SED) 's|^license = "LGPL-2.1-or-later"$$|license = { text = "LGPL-2.1-or-later" }|g' \
		$(@D)/pyproject.toml
endef
PYTHON_PY7ZR_POST_PATCH_HOOKS += PYTHON_PY7ZR_FIX_PYPROJECT_LICENSE

define PYTHON_PY7ZR_RELAX_BUILD_BACKEND_REQS
	$(SED) 's|setuptools>=80|setuptools|g' $(@D)/pyproject.toml
	$(SED) 's|setuptools_scm\\[toml\\]>=9.2.0|setuptools_scm[toml]|g' $(@D)/pyproject.toml
endef
PYTHON_PY7ZR_POST_PATCH_HOOKS += PYTHON_PY7ZR_RELAX_BUILD_BACKEND_REQS

$(eval $(python-package))
