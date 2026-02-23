################################################################################
#
# python-evtx
#
################################################################################

PYTHON_EVTX_VERSION = 0.8.1
PYTHON_EVTX_SOURCE = python_evtx-0.8.1.tar.gz
PYTHON_EVTX_SITE = https://files.pythonhosted.org/packages/34/44/e28f31531834b1cd93d14472ec84136dad565e9db0f7abcbae96176c1e65
PYTHON_EVTX_SETUP_TYPE = setuptools
PYTHON_EVTX_LICENSE = UNKNOWN

$(eval $(python-package))
