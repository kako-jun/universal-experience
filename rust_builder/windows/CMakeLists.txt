cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "universal_experience_rust")
project(${PROJECT_NAME} LANGUAGES CXX)

# FFI-only plugin: cargokit creates an ALL target and returns the DLL path.
include("../cargokit/cmake/cargokit.cmake")
apply_cargokit(${PROJECT_NAME} ../../rust universal_experience_rust "")

set(universal_experience_rust_bundled_libraries
  "${${PROJECT_NAME}_cargokit_lib}"
  PARENT_SCOPE
)
