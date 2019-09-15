# Copyright (c) 2019 Ultimaker B.V.
# Cura is released under the terms of the LGPLv3 or higher.
from UM import i18nCatalog
from UM.Message import Message


I18N_CATALOG = i18nCatalog("cura")


## Message shown when trying to connect to a legacy printer device.
class LegacyDeviceNoLongerSupportedMessage(Message):
    
    # Singleton used to prevent duplicate messages of this type at the same time.
    __is_visible = False
    
    def __init__(self) -> None:
        super().__init__(
            text = I18N_CATALOG.i18nc("@info:status", "You are attempting to connect to a printer that is not "
                                                      "running Ultimaker Connect. Please update the printer to the "
                                                      "latest firmware."),
            title = I18N_CATALOG.i18nc("@info:title", "Update your printer"),
            lifetime = 10
        )

    def show(self) -> None:
        if LegacyDeviceNoLongerSupportedMessage.__is_visible:
            return
        super().show()
        LegacyDeviceNoLongerSupportedMessage.__is_visible = True

    def hide(self, send_signal = True) -> None:
        super().hide(send_signal)
        LegacyDeviceNoLongerSupportedMessage.__is_visible = False
