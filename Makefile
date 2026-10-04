TARGET := iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SimGPSInApp

SimGPSInApp_FILES = Tweak.x FLLocationHook.x FLLocationConfig.m FLLocationEngine.m FLLocationService.m FLUI.m
SimGPSInApp_CFLAGS = -fobjc-arc
SimGPSInApp_FRAMEWORKS = CoreLocation UIKit CoreGraphics

include $(THEOS_MAKE_PATH)/tweak.mk