################################################################################
#
# python-tbtrim
#
################################################################################

PYTHON_TBTRIM_VERSION = 0.3.1
PYTHON_TBTRIM_SOURCE = tbtrim-$(PYTHON_TBTRIM_VERSION).tar.gz
PYTHON_TBTRIM_SITE = https://files.pythonhosted.org/packages/85/62/89756f5d2d61691591c4293fd4cc1fbb3aab1466251c7319fe60dd08fb27
PYTHON_TBTRIM_SETUP_TYPE = setuptools
PYTHON_TBTRIM_LICENSE = UNKNOWN

$(eval $(python-package))
