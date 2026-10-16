# Writes the Firefox version of the browser extension's manifest from the Chrome one, so both stay
# in step: Firefox runs the background script as an event page, identifies the extension by its
# gecko id instead of a key, and needs Firefox 128+ for MAIN-world content scripts (passkeys).
file(READ "${CMAKE_CURRENT_LIST_DIR}/../browser_extension/manifest.json" OB_MANIFEST)
string(JSON OB_MANIFEST REMOVE "${OB_MANIFEST}" key)
string(JSON OB_MANIFEST REMOVE "${OB_MANIFEST}" minimum_chrome_version)
string(JSON OB_MANIFEST SET "${OB_MANIFEST}" background "{\"scripts\": [\"background.js\"]}")
string(JSON OB_MANIFEST SET "${OB_MANIFEST}" browser_specific_settings
  "{\"gecko\": {\"id\": \"passwords@openbubbles\", \"strict_min_version\": \"128.0\", \"data_collection_permissions\": {\"required\": [\"none\"]}}}")
file(WRITE "${CMAKE_BINARY_DIR}/firefox_extension/manifest.json" "${OB_MANIFEST}")
