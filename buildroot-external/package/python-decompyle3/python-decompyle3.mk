################################################################################
#
# python-decompyle3
#
################################################################################

PYTHON_DECOMPYLE3_VERSION = 3.9.3
PYTHON_DECOMPYLE3_SOURCE = decompyle3-3.9.3.tar.gz
PYTHON_DECOMPYLE3_SITE = https://files.pythonhosted.org/packages/0e/db/a610ef067904ad273cb5fdb020c68bf5d1565a4a2de7f07c25877e462240
PYTHON_DECOMPYLE3_SETUP_TYPE = setuptools
PYTHON_DECOMPYLE3_LICENSE = GPL3
PYTHON_DECOMPYLE3_DEPENDENCIES = python-spark-parser python-xdis

$(eval $(python-package))
