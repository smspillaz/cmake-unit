# /tests/InitialCacheWrittenAfterTestAdded.cmake
#
# Ensure that ${CMAKE_CURRENT_BINARY_DIR}/${TEST_NAME}/initial_cache.cmake
# is written out after cmake_unit_config_test
#
# See LICENCE.md for Copyright information

set (TEST_NAME SampleTest)
file (WRITE "${CMAKE_CURRENT_SOURCE_DIR}/${TEST_NAME}.cmake" "")

include (CMakeUnit)
include (CMakeUnitRunner)

cmake_unit_init ()

cmake_unit_config_test (${TEST_NAME})

set (INITIAL_CACHE_FILE
     "${CMAKE_CURRENT_BINARY_DIR}/${TEST_NAME}/initial_cache.cmake")
cmake_unit_assert_file_exists ("${INITIAL_CACHE_FILE}")
