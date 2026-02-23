################################################################################
#
# python-unicorn
#
################################################################################

PYTHON_UNICORN_VERSION = 2.1.4
PYTHON_UNICORN_SOURCE = unicorn-2.1.4.tar.gz
PYTHON_UNICORN_SITE = https://files.pythonhosted.org/packages/b2/1b/b4248aa8422e86de690cf8e85cf8feae4c33405a097d1ebe71570bdaa6f5
PYTHON_UNICORN_SETUP_TYPE = setuptools
PYTHON_UNICORN_LICENSE = BSD License

$(eval $(python-package))
