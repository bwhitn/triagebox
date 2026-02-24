################################################################################
#
# python-binary-refinery
#
################################################################################

PYTHON_BINARY_REFINERY_VERSION ?= 0.9.26
PYTHON_LIEF_VERSION ?= 0.17.3
PYTHON_BINARY_REFINERY_WHEELHOUSE_DIR ?=
PYTHON_BINARY_REFINERY_REQUIRE_PREFETCH ?= 0
PYTHON_BINARY_REFINERY_WHEEL_PLATFORM_PRIMARY ?= manylinux_2_28_i686
PYTHON_BINARY_REFINERY_WHEEL_PLATFORM_FALLBACK ?= manylinux2014_i686
PYTHON_BINARY_REFINERY_COMMAND_PREFIX ?=
PYTHON_BINARY_REFINERY_SOURCE = binary_refinery-$(PYTHON_BINARY_REFINERY_VERSION).tar.gz
PYTHON_BINARY_REFINERY_SITE = https://files.pythonhosted.org/packages/source/b/binary-refinery
PYTHON_BINARY_REFINERY_LICENSE = MIT
PYTHON_BINARY_REFINERY_LICENSE_FILES = LICENSE.md
PYTHON_BINARY_REFINERY_SETUP_TYPE = setuptools
PYTHON_BINARY_REFINERY_DEPENDENCIES = host-python-pip host-python-installer host-python-toml
PYTHON_BINARY_REFINERY_ENV = REFINERY_PREFIX=$(PYTHON_BINARY_REFINERY_COMMAND_PREFIX)

PYTHON_BINARY_REFINERY_PYTAG = cp$(subst .,,$(PYTHON3_VERSION_MAJOR))
PYTHON_BINARY_REFINERY_REQUIREMENTS_FILE = \
	$(BR2_EXTERNAL_NIXBROWSER_PATH)/package/python-binary-refinery/requirements-all.txt
PYTHON_BINARY_REFINERY_PREFETCHED_REQUIREMENTS_FILE = \
	$(PYTHON_BINARY_REFINERY_WHEELHOUSE_DIR)/requirements-resolved.txt

# binary-refinery setup.py eagerly reloads all units and dynamically computes
# extras during wheel build. That aborts cross-builds when optional runtime
# deps are not yet present in the host build environment. We install runtime
# deps separately from wheelhouse downloads below, so bypass both paths.
define PYTHON_BINARY_REFINERY_RELAX_SETUP_EXTRAS
	$(SED) '/^    with refinery.__unit_loader__ as ldr:$$/{N;s|^    with refinery.__unit_loader__ as ldr:\n        ldr.reload()$$|    pass|;}' $(@D)/setup.py
	$(SED) 's|extras = get_setup_extras(requirements)|extras = {}|g' $(@D)/setup.py
	printf '%s\n' \
		'[build-system]' \
		'requires = [' \
		'    "setuptools",' \
		'    "toml",' \
		'    "wheel",' \
		']' \
		'build-backend = "setuptools.build_meta"' \
		> $(@D)/pyproject.toml
endef
PYTHON_BINARY_REFINERY_POST_PATCH_HOOKS += PYTHON_BINARY_REFINERY_RELAX_SETUP_EXTRAS

define PYTHON_BINARY_REFINERY_INSTALL_ALL_DEPS
	rm -rf $(@D)/wheelhouse
	mkdir -p $(@D)/wheelhouse
	if [ "$(PYTHON_BINARY_REFINERY_REQUIRE_PREFETCH)" = "1" ] && [ -f "$(PYTHON_BINARY_REFINERY_PREFETCHED_REQUIREMENTS_FILE)" ]; then \
		cp "$(PYTHON_BINARY_REFINERY_PREFETCHED_REQUIREMENTS_FILE)" $(@D)/requirements-all.txt; \
	else \
		cp $(PYTHON_BINARY_REFINERY_REQUIREMENTS_FILE) $(@D)/requirements-all.txt; \
		printf '%s\n' 'lief==$(PYTHON_LIEF_VERSION)' >> $(@D)/requirements-all.txt; \
	fi
	if [ -n "$(PYTHON_BINARY_REFINERY_WHEELHOUSE_DIR)" ] && [ -d "$(PYTHON_BINARY_REFINERY_WHEELHOUSE_DIR)" ]; then \
		find "$(PYTHON_BINARY_REFINERY_WHEELHOUSE_DIR)" -maxdepth 1 -type f -name '*.whl' -exec cp -f {} $(@D)/wheelhouse/ \; ; \
	fi
	if [ "$(PYTHON_BINARY_REFINERY_REQUIRE_PREFETCH)" = "1" ]; then \
		PIP_DISABLE_PIP_VERSION_CHECK=1 \
		PIP_NO_CACHE_DIR=1 \
		$(HOST_DIR)/bin/python3 -m pip download \
			--no-index \
			--find-links $(@D)/wheelhouse \
			--only-binary=:all: \
			--platform $(PYTHON_BINARY_REFINERY_WHEEL_PLATFORM_PRIMARY) \
			--platform $(PYTHON_BINARY_REFINERY_WHEEL_PLATFORM_FALLBACK) \
			--implementation cp \
			--python-version $(subst .,,$(PYTHON3_VERSION_MAJOR)) \
			--abi $(PYTHON_BINARY_REFINERY_PYTAG) \
			--dest $(@D)/wheelhouse \
			-r $(@D)/requirements-all.txt; \
	else \
		PIP_DISABLE_PIP_VERSION_CHECK=1 \
		PIP_NO_CACHE_DIR=1 \
		$(HOST_DIR)/bin/python3 -m pip download \
			--find-links $(@D)/wheelhouse \
			--only-binary=:all: \
			--platform $(PYTHON_BINARY_REFINERY_WHEEL_PLATFORM_PRIMARY) \
			--platform $(PYTHON_BINARY_REFINERY_WHEEL_PLATFORM_FALLBACK) \
			--implementation cp \
			--python-version $(subst .,,$(PYTHON3_VERSION_MAJOR)) \
			--abi $(PYTHON_BINARY_REFINERY_PYTAG) \
			--dest $(@D)/wheelhouse \
			-r $(@D)/requirements-all.txt; \
	fi
	if [ -n "$(PYTHON_BINARY_REFINERY_WHEELHOUSE_DIR)" ]; then \
		mkdir -p "$(PYTHON_BINARY_REFINERY_WHEELHOUSE_DIR)"; \
		find $(@D)/wheelhouse -maxdepth 1 -type f -name '*.whl' -exec cp -f {} "$(PYTHON_BINARY_REFINERY_WHEELHOUSE_DIR)/" \; ; \
	fi
	set -e; \
	for wheel in $$(find $(@D)/wheelhouse -maxdepth 1 -type f -name '*.whl' | sort); do \
		$(HOST_DIR)/bin/python3 -m installer \
			--destdir=$(TARGET_DIR) \
			--prefix=/usr \
			"$$wheel"; \
	done
	rm -rf $(@D)/wheelhouse $(@D)/requirements-all.txt
endef
PYTHON_BINARY_REFINERY_POST_INSTALL_TARGET_HOOKS += PYTHON_BINARY_REFINERY_INSTALL_ALL_DEPS

$(eval $(python-package))
