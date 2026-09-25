# JumioObserver — observe-only KYC diagnostic tweak (Phase A)
#
# Dumps the FINAL images that PaysafeCard sends to Jumio, plus their metadata,
# so the user can see exactly what reached the verification server:
#   - selfie (JDAImage sent to the Jumio Liveness client)
#   - ID front/back (AVCapturePhotoOutput captures)
#   - upload metadata (URL, headers, nonce, dimensions, rotation/mirror flags)
#
# NO bypass, NO mutation — pure observation. Every dump preserves originals.

ARCHS := arm64 arm64e
TARGET := iphone:clang:16.5:16.5
INSTALL_TARGET_PROCESSES := PaysafeCard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = JumioObserver

JumioObserver_FILES = Tweak.x
JumioObserver_CFLAGS = -fobjc-arc -Wno-error
JumioObserver_LIBRARIES = 
JumioObserver_FRAMEWORKS = Foundation UIKit CoreGraphics ImageIO AVFoundation

include $(THEOS_MAKE_PATH)/tweak.mk
