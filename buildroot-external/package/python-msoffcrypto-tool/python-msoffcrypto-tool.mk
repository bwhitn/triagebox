################################################################################
#
# python-msoffcrypto-tool
#
################################################################################

PYTHON_MSOFFCRYPTO_TOOL_VERSION = 6.0.0
PYTHON_MSOFFCRYPTO_TOOL_SOURCE = msoffcrypto_tool-6.0.0.tar.gz
PYTHON_MSOFFCRYPTO_TOOL_SITE = https://files.pythonhosted.org/packages/a6/34/6250bdddaeaae24098e45449ea362fb3555a65fba30cad0ad5630ea48d1a
PYTHON_MSOFFCRYPTO_TOOL_SETUP_TYPE = pep517
PYTHON_MSOFFCRYPTO_TOOL_LICENSE = MIT

$(eval $(python-package))
