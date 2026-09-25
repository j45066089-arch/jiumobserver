ARCHS := arm64 arm64e
TARGET := iphone:clang:16.5:16.5
INSTALL_TARGET_PROCESSES := PaysafeCard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = JumioProbe

JumioProbe_FILES = Probe.x
JumioProbe_CFLAGS = -fobjc-arc -Wno-error

include $(THEOS_MAKE_PATH)/tweak.mk
