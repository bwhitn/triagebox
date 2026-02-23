################################################################################
#
# python-speakeasy-emulator-refined
#
################################################################################

PYTHON_SPEAKEASY_EMULATOR_REFINED_VERSION = 1.6.1b0.post3
PYTHON_SPEAKEASY_EMULATOR_REFINED_SOURCE = speakeasy_emulator_refined-1.6.1b0.post3.tar.gz
PYTHON_SPEAKEASY_EMULATOR_REFINED_SITE = https://files.pythonhosted.org/packages/3d/93/a74a1af7ea6b3957c845c9b4f341f9d4f15884b0d2116572b0b749ea9940
PYTHON_SPEAKEASY_EMULATOR_REFINED_SETUP_TYPE = setuptools
PYTHON_SPEAKEASY_EMULATOR_REFINED_LICENSE = UNKNOWN

define PYTHON_SPEAKEASY_EMULATOR_REFINED_ENSURE_REQUIREMENTS
	if [ ! -f $(@D)/requirements.txt ]; then \
		printf '%s\n' '# Buildroot shim: sdist is missing requirements.txt' > $(@D)/requirements.txt; \
	fi
endef
PYTHON_SPEAKEASY_EMULATOR_REFINED_POST_PATCH_HOOKS += PYTHON_SPEAKEASY_EMULATOR_REFINED_ENSURE_REQUIREMENTS

$(eval $(python-package))
