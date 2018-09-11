
set(proj NUMPY)

# Set dependency list
set(${proj}_DEPENDENCIES python python-setuptools python-nose)

if(NOT DEFINED Slicer_USE_SYSTEM_${proj})
  set(Slicer_USE_SYSTEM_${proj} ${Slicer_USE_SYSTEM_python})
endif()

# Include dependent projects if any
ExternalProject_Include_Dependencies(${proj} PROJECT_VAR proj DEPENDS_VAR ${proj}_DEPENDENCIES)

if(Slicer_USE_SYSTEM_${proj})
  ExternalProject_FindPythonPackage(
    MODULE_NAME "numpy"
    REQUIRED
    )
endif()

if(NOT Slicer_USE_SYSTEM_NUMPY)

  ExternalProject_Message(${proj} "${proj} - Building without Fortran compiler - Non-optimized code will be built !")

  set(EP_SOURCE_DIR ${CMAKE_BINARY_DIR}/${proj})

  include(ExternalProjectForNonCMakeProject)

  # environment
  set(_env_script ${CMAKE_BINARY_DIR}/${proj}_Env.cmake)
  ExternalProject_Write_SetBuildEnv_Commands(${_env_script})
  ExternalProject_Write_SetPythonSetupEnv_Commands(${_env_script} APPEND)
  file(APPEND ${_env_script}
"#------------------------------------------------------------------------------
# Added by '${CMAKE_CURRENT_LIST_FILE}'

set(ENV{F77} \"\")
set(ENV{F90} \"\")
set(ENV{FFLAGS} \"\")

# See http://docs.scipy.org/doc/numpy/user/install.html#disabling-atlas-and-other-accelerated-libraries
# and http://massmail.spl.harvard.edu/public-archives/slicer-devel/2013/011098.html
set(ENV{ATLAS} \"None\")
set(ENV{BLAS} \"None\")
set(ENV{LAPACK} \"None\")
set(ENV{MKL} \"None\")
")

  # configure step
  set(_configure_script ${CMAKE_BINARY_DIR}/${proj}_configure_step.cmake)
  file(WRITE ${_configure_script}
"include(\"${_env_script}\")
set(${proj}_WORKING_DIR \"${EP_SOURCE_DIR}\")
file(WRITE \"${EP_SOURCE_DIR}/site.cfg\" \"\")
ExternalProject_Execute(${proj} \"configure\" \"${PYTHON_EXECUTABLE}\" setup.py config)
")

  # build step
  set(_build_script ${CMAKE_BINARY_DIR}/${proj}_build_step.cmake)
  file(WRITE ${_build_script}
"include(\"${_env_script}\")
set(${proj}_WORKING_DIR \"${EP_SOURCE_DIR}\")
ExternalProject_Execute(${proj} \"build\" \"${PYTHON_EXECUTABLE}\" setup.py build --fcompiler=none)
")

  # install step
  set(_install_script ${CMAKE_BINARY_DIR}/${proj}_install_step.cmake)
  file(WRITE ${_install_script}
"include(\"${_env_script}\")
set(${proj}_WORKING_DIR \"${EP_SOURCE_DIR}\")
ExternalProject_Execute(${proj} \"install\" \"${PYTHON_EXECUTABLE}\" setup.py install)
")

  set(_version "1.15.1")

  if(CMAKE_CONFIGURATION_TYPES)
    set(_download_stamp "${Slicer_BINARY_DIR}/${proj}-prefix/src/${proj}-stamp/${CMAKE_CFG_INTDIR}/${proj}-download")
  else()
    set(_download_stamp "${Slicer_BINARY_DIR}/${proj}-prefix/src/${proj}-stamp/${proj}-download")
  endif()
  set(_common_patch_args
    -DPatch_EXECUTABLE:PATH=${Patch_EXECUTABLE}
    -DSOURCE_DIR:PATH=<SOURCE_DIR>
    -DBINARY_DIR:PATH=${CMAKE_BINARY_DIR}
    -DDOWNLOAD_STAMP:FILEPATH=${_download_stamp}
    )

  #------------------------------------------------------------------------------
  ExternalProject_Add(${proj}
    ${${proj}_EP_ARGS}
    URL "https://files.pythonhosted.org/packages/65/ab/4dfcc20234fae12ee40c714b98077d6e3a10652496bd1488fa4828529b22/numpy-${_version}.zip"
    URL_HASH SHA256=7b9e37f194f8bcdca8e9e6af92e2cbad79e360542effc2dd6b98d63955d8d8a3
    DOWNLOAD_DIR ${CMAKE_BINARY_DIR}
    SOURCE_DIR ${EP_SOURCE_DIR}
    BUILD_IN_SOURCE 1
    PATCH_COMMAND
      #
      # To allow building without a Fortran compiler, effectively back out this change:
      # https://github.com/numpy/numpy/commit/4a3fd1f40ef59b872341088a2e97712c671ea4ca
      COMMAND ${CMAKE_COMMAND} ${_common_patch_args}
        -DPATCH:FILEPATH=${CMAKE_CURRENT_LIST_DIR}/numpy-02-fcompiler-optional-revert-4a3fd1f.patch
        -P ${Slicer_SOURCE_DIR}/CMake/SlicerPatch.cmake
      #
      # Ignore "RuntimeWarning: invalid value encountered in power"
      # See https://discourse.slicer.org/t/runtime-warning-on-startup-in-numpy/757/10
      COMMAND ${CMAKE_COMMAND} ${_common_patch_args}
         -DPATCH:FILEPATH=${CMAKE_CURRENT_LIST_DIR}/numpy-03-core-getlimits-ignore-warnings.patch
        -P ${Slicer_SOURCE_DIR}/CMake/SlicerPatch.cmake
      #
      # Disable check for Python 3 when using flang
      COMMAND ${CMAKE_COMMAND} ${_common_patch_args}
         -DPATCH:FILEPATH=${CMAKE_CURRENT_LIST_DIR}/numpy-04-allow-flang-python2.patch
         -P ${Slicer_SOURCE_DIR}/CMake/SlicerPatch.cmake
      #
      # Remove /Og option from /Ox MSVC optimization flag due to crash when building SciPy
      COMMAND ${CMAKE_COMMAND} ${_common_patch_args}
         -DPATCH:FILEPATH=${CMAKE_CURRENT_LIST_DIR}/numpy-05-fix-msvc-flags.patch
         -P ${Slicer_SOURCE_DIR}/CMake/SlicerPatch.cmake
    CONFIGURE_COMMAND ${CMAKE_COMMAND} -P ${_configure_script}
    BUILD_COMMAND ${CMAKE_COMMAND} -P ${_build_script}
    INSTALL_COMMAND ${CMAKE_COMMAND} -P ${_install_script}
    DEPENDS
      ${${proj}_DEPENDENCIES}
    )

  ExternalProject_GenerateProjectDescription_Step(${proj}
    VERSION ${_version}
    )

  #-----------------------------------------------------------------------------
  # Sanity checks

  foreach(varname IN ITEMS
      python_DIR
      PYTHON_SITE_PACKAGES_SUBDIR
      )
    if("${${varname}}" STREQUAL "")
      message(FATAL_ERROR "${varname} CMake variable is expected to be set")
    endif()
  endforeach()

  #-----------------------------------------------------------------------------
  # Launcher setting specific to build tree

  set(${proj}_LIBRARY_PATHS_LAUNCHER_BUILD
    ${python_DIR}/${PYTHON_SITE_PACKAGES_SUBDIR}/numpy/core
    ${python_DIR}/${PYTHON_SITE_PACKAGES_SUBDIR}/numpy/lib
    )
  mark_as_superbuild(
    VARS ${proj}_LIBRARY_PATHS_LAUNCHER_BUILD
    LABELS "LIBRARY_PATHS_LAUNCHER_BUILD"
    )

  #-----------------------------------------------------------------------------
  # Launcher setting specific to install tree

  set(${proj}_LIBRARY_PATHS_LAUNCHER_INSTALLED
    <APPLAUNCHER_SETTINGS_DIR>/../lib/Python/${PYTHON_SITE_PACKAGES_SUBDIR}/numpy/core
    <APPLAUNCHER_SETTINGS_DIR>/../lib/Python/${PYTHON_SITE_PACKAGES_SUBDIR}/numpy/lib
    )
  mark_as_superbuild(
    VARS ${proj}_LIBRARY_PATHS_LAUNCHER_INSTALLED
    LABELS "LIBRARY_PATHS_LAUNCHER_INSTALLED"
    )

else()
  ExternalProject_Add_Empty(${proj} DEPENDS ${${proj}_DEPENDENCIES})
endif()
