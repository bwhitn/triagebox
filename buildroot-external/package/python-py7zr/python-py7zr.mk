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

define PYTHON_PY7ZR_FIX_PYPROJECT_LICENSE
	$(SED) 's|^license = "LGPL-2.1-or-later"$$|license = { text = "LGPL-2.1-or-later" }|g' \
		$(@D)/pyproject.toml
endef
PYTHON_PY7ZR_POST_PATCH_HOOKS += PYTHON_PY7ZR_FIX_PYPROJECT_LICENSE

$(eval $(python-package))
