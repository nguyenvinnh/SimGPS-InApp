TARGET := iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = fakelocation

fakelocation_FILES = Tweak.x FLLocationHook.x FLLocationConfig.m FLLocationEngine.m FLLocationService.m FLUI.m
fakelocation_CFLAGS = -fobjc-arc
fakelocation_FRAMEWORKS = CoreLocation UIKit CoreGraphics

include $(THEOS_MAKE_PATH)/tweak.mk