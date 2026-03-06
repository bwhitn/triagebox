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
PYTHON_BINARY_REFINERY_COMMAND_PREFIX ?= ref-
PYTHON_BINARY_REFINERY_PYTHON_OPTIMIZE ?= 1
PYTHON_BINARY_REFINERY_SOURCE = binary_refinery-$(PYTHON_BINARY_REFINERY_VERSION).tar.gz
PYTHON_BINARY_REFINERY_SITE = https://files.pythonhosted.org/packages/source/b/binary-refinery
PYTHON_BINARY_REFINERY_LICENSE = MIT
PYTHON_BINARY_REFINERY_LICENSE_FILES = LICENSE.md
PYTHON_BINARY_REFINERY_SETUP_TYPE = setuptools
PYTHON_BINARY_REFINERY_DEPENDENCIES = host-python-pip host-python-installer host-python-toml
PYTHON_BINARY_REFINERY_ENV = REFINERY_PREFIX=

PYTHON_BINARY_REFINERY_PYTAG = cp$(subst .,,$(PYTHON3_VERSION_MAJOR))
PYTHON_BINARY_REFINERY_REQUIREMENTS_FILE = \
	$(BR2_EXTERNAL_TRIAGEBOX_PATH)/package/python-binary-refinery/requirements-all.txt
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

# Some serial console setups report terminal width/height as zero in non-standard
# PTY chains. refinery/lib/tools.py passes that to textwrap, which raises
# "ValueError: invalid width 0". Patch terminalfit to guard COLUMNS/LINES.
define PYTHON_BINARY_REFINERY_PATCH_TERMINALFIT
	if [ -f $(@D)/refinery/lib/tools.py ] && \
		! grep -q '__TRIAGEBOX_TERMINALFIT_GUARD__' $(@D)/refinery/lib/tools.py; then \
		printf '\n%s\n' \
			'# __TRIAGEBOX_TERMINALFIT_GUARD__' \
			'try:' \
			'    _triagebox_terminalfit_original = terminalfit' \
			'except NameError:' \
			'    _triagebox_terminalfit_original = None' \
			'' \
			'if _triagebox_terminalfit_original is not None:' \
			'    def terminalfit(*args, **kwargs):' \
			'        import os as _triagebox_os' \
			'        _triagebox_cols = _triagebox_os.environ.get("COLUMNS", "")' \
			'        if not _triagebox_cols.isdigit() or int(_triagebox_cols) <= 0:' \
			'            _triagebox_os.environ["COLUMNS"] = "120"' \
			'        _triagebox_lines = _triagebox_os.environ.get("LINES", "")' \
			'        if not _triagebox_lines.isdigit() or int(_triagebox_lines) <= 0:' \
			'            _triagebox_os.environ["LINES"] = "40"' \
			'        return _triagebox_terminalfit_original(*args, **kwargs)' \
			>> $(@D)/refinery/lib/tools.py; \
	fi
endef
PYTHON_BINARY_REFINERY_POST_PATCH_HOOKS += PYTHON_BINARY_REFINERY_PATCH_TERMINALFIT

# importlib.resources is surprisingly expensive during startup in this target
# environment. binary-refinery resources are always on a normal filesystem path
# here, so replace datapath() with a direct Path-based fast path.
define PYTHON_BINARY_REFINERY_PATCH_RESOURCES_FASTPATH
	resources_py="$(@D)/refinery/lib/resources.py"; \
	if [ -f "$$resources_py" ] && ! grep -q '__TRIAGEBOX_RESOURCES_FASTPATH__' "$$resources_py"; then \
		printf '%s\n' \
			'"""A wrapper module to read local data resources."""' \
			'from __future__ import annotations' \
			'' \
			'from pathlib import Path' \
			'' \
			'_DATA_DIR = Path(__file__).resolve().parent.parent / "data"' \
			'' \
			'' \
			'def datapath(name: str):' \
			'    # __TRIAGEBOX_RESOURCES_FASTPATH__' \
			'    return _DATA_DIR / name' \
			> "$$resources_py"; \
	fi
endef
PYTHON_BINARY_REFINERY_POST_PATCH_HOOKS += PYTHON_BINARY_REFINERY_PATCH_RESOURCES_FASTPATH

define PYTHON_BINARY_REFINERY_PATCH_TERMINALFIT_TARGET
	tools_py="$(TARGET_DIR)/usr/lib/python$(PYTHON3_VERSION_MAJOR)/site-packages/refinery/lib/tools.py"; \
	if [ -f "$$tools_py" ] && \
		! grep -q '__TRIAGEBOX_TERMINALFIT_GUARD_V2__' "$$tools_py"; then \
		printf '\n%s\n' \
			'# __TRIAGEBOX_TERMINALFIT_GUARD_V2__' \
			'try:' \
			'    _triagebox_terminalfit_original_v2 = terminalfit' \
			'except NameError:' \
			'    _triagebox_terminalfit_original_v2 = None' \
			'' \
			'if _triagebox_terminalfit_original_v2 is not None:' \
			'    def terminalfit(*args, **kwargs):' \
			'        import os as _triagebox_os' \
			'        import shutil as _triagebox_shutil' \
			'        _triagebox_size = _triagebox_shutil.get_terminal_size((120, 40))' \
			'        _triagebox_cols = str(max(2, _triagebox_size.columns))' \
			'        _triagebox_lines = str(max(2, _triagebox_size.lines))' \
			'        _triagebox_colenv = _triagebox_os.environ.get("COLUMNS", "")' \
			'        _triagebox_lineenv = _triagebox_os.environ.get("LINES", "")' \
			'        if (not _triagebox_colenv.isdigit()) or int(_triagebox_colenv) <= 1:' \
			'            _triagebox_os.environ["COLUMNS"] = _triagebox_cols' \
			'        if (not _triagebox_lineenv.isdigit()) or int(_triagebox_lineenv) <= 1:' \
			'            _triagebox_os.environ["LINES"] = _triagebox_lines' \
			'        if "width" in kwargs:' \
			'            try:' \
			'                if int(kwargs.get("width") or 0) <= 1:' \
			'                    kwargs["width"] = int(_triagebox_os.environ["COLUMNS"])' \
			'            except Exception:' \
			'                kwargs["width"] = int(_triagebox_os.environ["COLUMNS"])' \
			'        return _triagebox_terminalfit_original_v2(*args, **kwargs)' \
			>> "$$tools_py"; \
	fi
endef
PYTHON_BINARY_REFINERY_POST_INSTALL_TARGET_HOOKS += PYTHON_BINARY_REFINERY_PATCH_TERMINALFIT_TARGET

# Keep command startup predictable: do not auto-trigger full entry-point reload
# scans when the on-disk unit cache is missing/stale. The generated units.pkl
# is the fast path, and explicit reload can still be requested by tooling.
define PYTHON_BINARY_REFINERY_PATCH_LAZY_UNITS_TARGET
	init_py="$(TARGET_DIR)/usr/lib/python$(PYTHON3_VERSION_MAJOR)/site-packages/refinery/__init__.py"; \
	tmp_py="$(@D)/.__refinery_init_lazy.tmp"; \
	if [ -f "$$init_py" ] && ! grep -q '__TRIAGEBOX_REFINERY_LAZY_CACHE__' "$$init_py"; then \
		awk ' \
			/^        if cache is None:$$/ { \
				print $$0; \
				if (getline line > 0 && line ~ /^            self\\.reload\\(\\)$$/) { \
					print "            # __TRIAGEBOX_REFINERY_LAZY_CACHE__"; \
					print "            self.loaded = True"; \
					print "            return"; \
					next; \
				} \
				if (line != "") { print line; } \
				next; \
			} \
			{ print $$0; } \
		' "$$init_py" > "$$tmp_py"; \
		mv "$$tmp_py" "$$init_py"; \
	fi
endef
PYTHON_BINARY_REFINERY_POST_INSTALL_TARGET_HOOKS += PYTHON_BINARY_REFINERY_PATCH_LAZY_UNITS_TARGET

define PYTHON_BINARY_REFINERY_PATCH_EXPLORE_WIDTH_TARGET
	explore_py="$(TARGET_DIR)/usr/lib/python$(PYTHON3_VERSION_MAJOR)/site-packages/refinery/explore.py"; \
	if [ -f "$$explore_py" ] && ! grep -q '__TRIAGEBOX_EXPLORE_WIDTH_GUARD__' "$$explore_py"; then \
		$(HOST_DIR)/bin/python3 $(BR2_EXTERNAL_TRIAGEBOX_PATH)/../scripts/patch-refinery-explore.py "$$explore_py"; \
	fi
endef
PYTHON_BINARY_REFINERY_POST_INSTALL_TARGET_HOOKS += PYTHON_BINARY_REFINERY_PATCH_EXPLORE_WIDTH_TARGET

define PYTHON_BINARY_REFINERY_PREPARE_SCRIPT_STAGING
	rm -rf $(@D)/.scripts
	mkdir -p $(@D)/.scripts
endef
PYTHON_BINARY_REFINERY_PRE_INSTALL_TARGET_HOOKS += PYTHON_BINARY_REFINERY_PREPARE_SCRIPT_STAGING

define PYTHON_BINARY_REFINERY_INSTALL_TARGET_CMDS
	(cd $(@D)/; \
		$(PKG_PYTHON_SETUPTOOLS_ENV) \
		$(PYTHON_BINARY_REFINERY_ENV) \
		$(HOST_DIR)/bin/python3 \
		$(TOPDIR)/support/scripts/pyinstaller.py \
		dist/* \
		--interpreter=/usr/bin/python \
		--script-kind=posix \
		--purelib=$(TARGET_DIR)/usr/lib/python$(PYTHON3_VERSION_MAJOR)/site-packages \
		--headers=$(TARGET_DIR)/usr/include/python$(PYTHON3_VERSION_MAJOR) \
		--scripts=$(@D)/.scripts \
		--data=$(TARGET_DIR) \
		$(PYTHON_BINARY_REFINERY_INSTALL_TARGET_OPTS))
endef

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

define PYTHON_BINARY_REFINERY_INSTALL_SCRIPTS
	tmpdir="$(@D)/.scripts"; \
	bindir="$(TARGET_DIR)/usr/bin"; \
	prefix="$(PYTHON_BINARY_REFINERY_COMMAND_PREFIX)"; \
	optimize="$(PYTHON_BINARY_REFINERY_PYTHON_OPTIMIZE)"; \
	if [ -d "$$tmpdir" ]; then \
		mkdir -p "$$bindir"; \
		for src in "$$tmpdir"/*; do \
			[ -f "$$src" ] || continue; \
			name="$${src##*/}"; \
			dst="$$bindir/$$name"; \
			if [ -e "$$dst" ]; then \
				if grep -qi 'refinery' "$$dst" 2>/dev/null; then \
					rm -f "$$dst"; \
				elif [ -n "$$prefix" ]; then \
					case "$$name" in \
						$$prefix*) dst="$$bindir/$$name" ;; \
						*) dst="$$bindir/$$prefix$$name" ;; \
					esac; \
					if [ -e "$$dst" ] && grep -qi 'refinery' "$$dst" 2>/dev/null; then \
						rm -f "$$dst"; \
					fi; \
				fi; \
			fi; \
			if [ -e "$$dst" ]; then \
				rm -f "$$src"; \
				continue; \
			fi; \
			mv "$$src" "$$dst"; \
			chmod 0755 "$$dst"; \
			if [ "$$optimize" = "1" ] && [ -f "$$dst" ] && \
				head -n1 "$$dst" | grep -Eq '^#!.*python([0-9.]*)?([[:space:]].*)?$$'; then \
				$(SED) '1s@^#!.*$$@#!/usr/bin/python -O@' "$$dst"; \
			fi; \
		done; \
		rmdir "$$tmpdir" 2>/dev/null || true; \
	fi
endef
PYTHON_BINARY_REFINERY_POST_INSTALL_TARGET_HOOKS += PYTHON_BINARY_REFINERY_INSTALL_SCRIPTS

define PYTHON_BINARY_REFINERY_GENERATE_UNITS_CACHE
	bindir="$(TARGET_DIR)/usr/bin"; \
	pkgdir="$(TARGET_DIR)/usr/lib/python$(PYTHON3_VERSION_MAJOR)/site-packages/refinery"; \
	datadir="$$pkgdir/data"; \
	cache="$$datadir/units.pkl"; \
	mapfile="$(@D)/.units-map.tsv"; \
	epfile="$$(find "$(TARGET_DIR)/usr/lib/python$(PYTHON3_VERSION_MAJOR)/site-packages" -maxdepth 2 -type f \( \
		-path "*/binary_refinery-*.dist-info/entry_points.txt" -o \
		-path "*/binary_refinery-*.egg-info/entry_points.txt" -o \
		-path "*/binary_refinery.egg-info/entry_points.txt" \
	\) | head -n1 || true)"; \
	version="$(PYTHON_BINARY_REFINERY_VERSION)"; \
	mkdir -p "$$datadir"; \
	rm -f "$$mapfile"; \
	if [ -f "$$epfile" ]; then \
		sed -n "s/^[[:space:]]*[^=[:space:]]\\+[[:space:]]*=[[:space:]]*\\(refinery\\.units[^:[:space:]]*\\):\\([A-Za-z_][A-Za-z0-9_]*\\)\\.run[[:space:]]*$$/\\2\\t\\1/p" "$$epfile" > "$$mapfile"; \
	fi; \
	if [ ! -s "$$mapfile" ] && [ -d "$$bindir" ]; then \
		for script in "$$bindir"/*; do \
			[ -f "$$script" ] || continue; \
			entry="$$(sed -n "s/^from \\(refinery\\.units[^ ]*\\) import \\([A-Za-z_][A-Za-z0-9_]*\\)$$/\\2\\t\\1/p" "$$script" | head -n1)"; \
			[ -n "$$entry" ] || continue; \
			printf '%s\n' "$$entry" >> "$$mapfile"; \
		done; \
	fi; \
	if [ -s "$$mapfile" ] && [ -n "$$version" ]; then \
		$(HOST_DIR)/bin/python3 -c "import pathlib,pickle,sys; m=pathlib.Path(sys.argv[1]); o=pathlib.Path(sys.argv[2]); v=sys.argv[3]; u={}; [u.setdefault((p:=l.split('\t',1))[0], p[1]) for l in m.read_text(encoding='utf-8', errors='ignore').splitlines() if '\t' in l]; o.write_bytes(pickle.dumps({'units':u,'version':v}, protocol=4))" "$$mapfile" "$$cache" "$$version"; \
		chmod 0644 "$$cache"; \
	fi; \
	rm -f "$$mapfile"
endef
PYTHON_BINARY_REFINERY_POST_INSTALL_TARGET_HOOKS += PYTHON_BINARY_REFINERY_GENERATE_UNITS_CACHE

$(eval $(python-package))
