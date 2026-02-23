################################################################################
#
# python-uncompyle6
#
################################################################################

PYTHON_UNCOMPYLE6_VERSION = 3.9.3
PYTHON_UNCOMPYLE6_SOURCE = uncompyle6-3.9.3.tar.gz
PYTHON_UNCOMPYLE6_SITE = https://files.pythonhosted.org/packages/db/9b/c6ebd89902b60d397b5b992f58013fd0a29eee4ac87e46a7137a9a79b601
PYTHON_UNCOMPYLE6_SETUP_TYPE = setuptools
PYTHON_UNCOMPYLE6_LICENSE = GPL3

$(eval $(python-package))
