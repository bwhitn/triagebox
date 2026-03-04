################################################################################
#
# radare2
#
################################################################################

RADARE2_VERSION = 6.0.8
RADARE2_SOURCE = radare2-$(RADARE2_VERSION).tar.xz
RADARE2_SITE = https://github.com/radareorg/radare2/releases/download/$(RADARE2_VERSION)
RADARE2_LICENSE = LGPL-3.0+
RADARE2_LICENSE_FILES = COPYING.md
RADARE2_DEPENDENCIES = host-pkgconf

define RADARE2_CONFIGURE_CMDS
	(cd $(@D); \
		$(TARGET_CONFIGURE_OPTS) \
		$(TARGET_CONFIGURE_ARGS) \
		./configure \
			--prefix=/usr \
			--disable-debug-stuff \
			--without-gperf \
			--without-sysmagic)
endef

define RADARE2_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE1) -C $(@D)
endef

define RADARE2_INSTALL_TARGET_CMDS
	$(TARGET_MAKE_ENV) $(MAKE1) -C $(@D) DESTDIR=$(TARGET_DIR) install
	rm -rf $(TARGET_DIR)/usr/include/libr
	rm -rf $(TARGET_DIR)/usr/lib/pkgconfig
	rm -rf $(TARGET_DIR)/usr/share/doc/radare2
endef

$(eval $(generic-package))
