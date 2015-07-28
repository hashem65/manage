########################################################################
# These values will be put in place at generation phase.
# They could've also been passed over as command line definitions, however,
# this would allow to mess with them later. As this is the top level CMakeLists.txt
# for this specific compiler/mpi choice and sub-external projects rely on this
# choice, it's hard-coded rather than being modifiable (externally).
set(OPENCMISS_ROOT @OPENCMISS_ROOT@)
set(OPENCMISS_MANAGE_DIR @OPENCMISS_MANAGE_DIR@)
set(OPENCMISS_INSTALL_ROOT @CMAKE_INSTALL_PREFIX@)
########################################################################

# Set up include path
LIST(APPEND CMAKE_MODULE_PATH
    ${OPENCMISS_MANAGE_DIR}
    ${OPENCMISS_MANAGE_DIR}/CMakeScripts
    ${OPENCMISS_MANAGE_DIR}/Config)

# This includes the configuration, both default and local
include(OpenCMISSConfig)

########################################################################
@TOOLCHAIN_DEF@
SET(MPI @MPI@)
SET(OCM_SYSTEM_MPI @SYSTEM_MPI@)
SET(OCM_DEBUG_MPI @DEBUG_MPI@)
SET(MPI_BUILD_TYPE @MPI_BUILD_TYPE@)
@MPI_HOME_DEF@
########################################################################

# Need to set the compilers before any project call
include(ToolchainCompilers)

########################################################################
# Ready to start the "build project"
CMAKE_MINIMUM_REQUIRED(VERSION @OPENCMISS_CMAKE_MIN_VERSION@ FATAL_ERROR)
project(OpenCMISS VERSION ${OPENCMISS_VERSION} LANGUAGES C CXX Fortran)

# Need to set the compiler flags after any project call - this ensures the cmake platform values
# are used, too.
include(ToolchainFlags)

if ((NOT WIN32 OR MINGW) AND CMAKE_BUILD_TYPE STREQUAL "")
    SET(CMAKE_BUILD_TYPE RELEASE)
    message(STATUS "No CMAKE_BUILD_TYPE has been defined. Using RELEASE.")
endif()

include(ExternalProject)
include(OCMSetupArchitecture)
include(OCMSetupBuildMacros)

########################################################################
# Utilities
include(InstallFindModuleWrappers)
# Add CMakeModules directory after wrapper module directory (set in above script)
# This folder is also exported to the install tree upon "make install" and
# then used within the FindOpenCMISS.cmake module script
list(APPEND CMAKE_MODULE_PATH 
    ${OPENCMISS_MANAGE_DIR}/CMakeModules
)
include(DetectFortranMangling)

# Multithreading
if(OCM_USE_MT)
    find_package(OpenMP REQUIRED)
endif()

########################################################################
# MPI

# Unless we said to not have MPI or MPI_HOME is given, see that it's available.
if(NOT (DEFINED MPI_HOME OR MPI STREQUAL none))
    include(MPIConfig)
endif()
# Note:
# If MPI_HOME is set, we'll just pass it on to the external projects where the
# FindMPI.cmake module is going to look exclusively there.
# The availability of an MPI implementation at MPI_HOME was made sure
# in the MPIPreflight.cmake script upon generation time of this script.

# Checks for known issues as good as possible
# TODO: move this to the generator script (suitably)!
if (CMAKE_COMPILER_IS_GNUC AND MPI STREQUAL intel)
    message(FATAL_ERROR "Invalid compiler/MPI combination: Cannot build with GNU compiler and Intel MPI.")
endif()

########################################################################
# General paths & preps
get_architecture_path(ARCHITECTURE_PATH ARCHITECTURE_PATH_MPI)
# Build tree location for components (with/without mpi)
SET(OPENCMISS_COMPONENTS_BINARY_DIR ${OPENCMISS_ROOT}/build/${ARCHITECTURE_PATH})
SET(OPENCMISS_COMPONENTS_BINARY_DIR_MPI ${OPENCMISS_ROOT}/build/${ARCHITECTURE_PATH_MPI})
# Install dir
# Extra path segment for single configuration case - will give release/debug/...
get_build_type_extra(BUILDTYPEEXTRA)
# everything from the OpenCMISS main project goes into install/
set(OCM_COM_INST_PREFIX_MPI_NOBT ${OPENCMISS_INSTALL_ROOT}/${ARCHITECTURE_PATH_MPI})
SET(OPENCMISS_COMPONENTS_INSTALL_PREFIX ${OCM_COM_INST_PREFIX_MPI_NOBT}/${BUILDTYPEEXTRA})
SET(OPENCMISS_COMPONENTS_INSTALL_PREFIX_MPI ${OPENCMISS_INSTALL_ROOT}/${ARCHITECTURE_PATH_MPI}/${BUILDTYPEEXTRA})

######################
# The COMMON_PACKAGE_CONFIG_DIR contains the cmake-generated target config files consumed by find_package(... CONFIG).
# Those are "usually" placed under the lib/ folders of the installation tree, however, the OpenCMISS build system
# install trees also have the build type as subfolders. As the config-files generated natively create differently named files
# for each build type, they can be collected in a common subfolder. As the build type subfolder-element is the last in line,
# we simply use the parent folder of the component's CMAKE_INSTALL_PREFIX to place the cmake package config files.
# ATTENTION: this is (still) not usable. While older cmake versions deleted other-typed config files, they are now kept at least.
# However, having the config file OUTSIDE the install prefix path still does not work correctly, and the fact that
# we need to be able to determine build types for examples/iron/dependencies separately requires separate folders, for now.
SET(COMMON_PACKAGE_CONFIG_DIR cmake)
#SET(COMMON_PACKAGE_CONFIG_DIR ../cmake)
# The path where find_package calls will find the cmake package config files for any opencmiss component
set(OPENCMISS_PREFIX_PATH
    ${OPENCMISS_COMPONENTS_INSTALL_PREFIX}/${COMMON_PACKAGE_CONFIG_DIR} 
    ${OPENCMISS_COMPONENTS_INSTALL_PREFIX_MPI}/${COMMON_PACKAGE_CONFIG_DIR}
)

###################### 
# Prefix path assembly for remote installations of opencmiss dependencies
function(get_remote_prefix_path DIR)
    get_filename_component(DIR ${DIR} ABSOLUTE)
    if (EXISTS ${DIR}/context.cmake)
        include(${DIR}/context.cmake)
        set(REMOTE_PREFIX_PATH ${OPENCMISS_PREFIX_PATH} PARENT_SCOPE)
    endif()
endfunction()
# In case we are provided with a remote root directory, we are creating the same sub-path as we are locally using
# to import the matching libraries
if (OPENCMISS_DEPENDENCIES_ROOT)
    set(OPENCMISS_DEPENDENCIES_DIR ${OPENCMISS_DEPENDENCIES_ROOT}/${ARCHITECTURE_PATH}/${BUILDTYPEEXTRA})
endif()
# If we have a OPENCMISS_DEPENDENCIES_DIR, it's either provided directly or constructed from OPENCMISS_DEPENDENCIES_ROOT
if (OPENCMISS_DEPENDENCIES_DIR)
    # Need to wrap this into a function as a separate scope is needed in order to avoid overriding
    # local values by those set in the opencmiss context file.
    get_remote_prefix_path(${OPENCMISS_DEPENDENCIES_DIR})
    if (REMOTE_PREFIX_PATH)
        message(STATUS "Using remote OpenCMISS component installation at ${OPENCMISS_DEPENDENCIES_DIR}...")
        list(APPEND CMAKE_PREFIX_PATH ${REMOTE_PREFIX_PATH})
        unset(REMOTE_PREFIX_PATH) 
    else()
        if (OPENCMISS_DEPENDENCIES_ROOT)
            message(FATAL_ERROR "No OpenCMISS build context file (context.cmake) could be found using OPENCMISS_DEPENDENCIES_ROOT=${OPENCMISS_DEPENDENCIES_ROOT} (inferred OPENCMISS_DEPENDENCIES_DIR=${OPENCMISS_DEPENDENCIES_DIR})")
        else()
            message(FATAL_ERROR "No OpenCMISS build context file (context.cmake) could be found at OPENCMISS_DEPENDENCIES_DIR=${OPENCMISS_DEPENDENCIES_DIR}")
        endif()
    endif()
endif()

###################### 
# Collect the common arguments for any package/component
include(CollectComponentDefinitions)

#message(STATUS "OpenCMISS components common definitions:\n${COMPONENT_COMMON_DEFS}")

# Those list variables will be filled by the build macros
SET(_OCM_REQUIRED_SOURCES )
SET(_OCM_NEED_INITIAL_SOURCE_DOWNLOAD NO)

########################################################################
# Actual external project configurations

# Dependencies, Iron, ...
include(ConfigureComponents)

# Examples
include(AddExamplesProject)

########################################################################
# Installation stuff
set(OPENCMISS_CMAKE_MIN_VERSION @OPENCMISS_CMAKE_MIN_VERSION@)
include(Install)

########################################################################
# Misc targets for convenience
# update: Updates the whole source tree
# reset:

# Create a download target that depends on all other downloads
SET(_OCM_SOURCE_UPDATE_TARGETS )
#SET(_OCM_SOURCE_DOWNLOAD_TARGETS )
foreach(_COMP ${_OCM_REQUIRED_SOURCES})
    LIST(APPEND _OCM_SOURCE_UPDATE_TARGETS ${_COMP}_SRC-update)
    #LIST(APPEND _OCM_SOURCE_DOWNLOAD_TARGETS ${_COMP}_SRC-download)
endforeach()
add_custom_target(update
    DEPENDS ${_OCM_SOURCE_UPDATE_TARGETS}
)

# Need to enable testing in order for any add_test calls (see OCMSetupBuildMacros) to work
if (BUILD_TESTS)
    enable_testing()
endif()

# I already foresee that we will have to have "download" and "update" targets for the less insighted user.
# So lets just give it to them. Does the same as external project has initial download and update steps.
#add_custom_target(download
#    DEPENDS ${_OCM_SOURCE_DOWNLOAD_TARGETS}
#)
# Note: Added a <COMP>-SRC project that takes care to have the sources ready