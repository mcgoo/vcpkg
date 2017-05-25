## ## vcpkg_from_github
##
## Download and extract a project from GitHub. Enables support for `install --head`.
##
## ### Usage:
## ```cmake
## vcpkg_from_github(
##     OUT_SOURCE_PATH <SOURCE_PATH>
##     REPO <Microsoft/cpprestsdk>
##     [REF <v2.0.0>]
##     [SHA512 <45d0d7f8cc350...>]
##     [HEAD_REF <master>]
## )
## ```
##
## ### Parameters:
## #### `OUT_SOURCE_PATH`
## Specifies the out-variable that will contain the extracted location.
##
## This should be set to `SOURCE_PATH` by convention.
##
## #### `REPO`
## The organization or user and repository on GitHub.
##
## #### `REF`
## A stable git commit-ish (ideally a tag) that will not change contents.
##
## If `REF` is specified, `SHA512` must also be specified.
##
## #### `SHA512`
## The SHA512 hash that should match the archive (https://github.com/${REPO}/archive/${REF}.tar.gz).
##
## This is most easily determined by first setting it to `1`, then trying to build the port. The error message will contain the full hash, which can be copied back into the portfile.
##
## #### `HEAD_REF`
## The unstable git commit-ish (ideally a branch) to pull for `--head` builds.
##
## For most projects, this should be `master`. The chosen branch should be one that is expected to be always buildable on all supported platforms.
##
## ### Notes:
## At least one of `REF` and `HEAD_REF` must be specified.
##
## This exports the `VCPKG_HEAD_VERSION` variable during head builds.
##
## ### Examples:
##
## * [cpprestsdk](https://github.com/Microsoft/vcpkg/blob/master/ports/cpprestsdk/portfile.cmake)
## * [ms-gsl](https://github.com/Microsoft/vcpkg/blob/master/ports/ms-gsl/portfile.cmake)
## * [beast](https://github.com/Microsoft/vcpkg/blob/master/ports/beast/portfile.cmake)
function(vcpkg_from_github)
    set(oneValueArgs OUT_SOURCE_PATH REPO REF SHA512 HEAD_REF)
    set(multipleValuesArgs)
    cmake_parse_arguments(_vdud "" "${oneValueArgs}" "${multipleValuesArgs}" ${ARGN})

    if(NOT _vdud_OUT_SOURCE_PATH)
        message(FATAL_ERROR "OUT_SOURCE_PATH must be specified.")
    endif()

    if((_vdud_REF AND NOT _vdud_SHA512) OR (NOT _vdud_REF AND _vdud_SHA512))
        message(FATAL_ERROR "SHA512 must be specified if REF is specified.")
    endif()

    if(NOT _vdud_REPO)
        message(FATAL_ERROR "The GitHub repository must be specified.")
    endif()

    if(NOT _vdud_REF AND NOT _vdud_HEAD_REF)
        message(FATAL_ERROR "At least one of REF and HEAD_REF must be specified.")
    endif()

    string(REGEX REPLACE ".*/" "" REPO_NAME ${_vdud_REPO})
    string(REGEX REPLACE "/.*" "" ORG_NAME ${_vdud_REPO})

    macro(set_SOURCE_PATH BASE BASEREF)
        set(SOURCE_PATH "${BASE}/${REPO_NAME}-${BASEREF}")
        if(EXISTS ${SOURCE_PATH})
            set(${_vdud_OUT_SOURCE_PATH} "${SOURCE_PATH}" PARENT_SCOPE)
        else()
            # Sometimes GitHub strips a leading 'v' off the REF.
            string(REGEX REPLACE "^v" "" REF ${BASEREF})
            set(SOURCE_PATH "${BASE}/${REPO_NAME}-${REF}")
            if(EXISTS ${SOURCE_PATH})
                set(${_vdud_OUT_SOURCE_PATH} "${SOURCE_PATH}" PARENT_SCOPE)
            else()
                message(FATAL_ERROR "Could not determine source path: '${BASE}/${REPO_NAME}-${BASEREF}' does not exist")
            endif()
        endif()
    endmacro()

    if(VCPKG_USE_HEAD_VERSION AND NOT _vdud_HEAD_REF)
        message(STATUS "Package does not specify HEAD_REF. Falling back to non-HEAD version.")
        set(VCPKG_USE_HEAD_VERSION OFF)
    endif()

    # Handle --no-head scenarios
    if(NOT VCPKG_USE_HEAD_VERSION)
        if(NOT _vdud_REF)
            message(FATAL_ERROR "Package does not specify REF. It must built using --head.")
        endif()

        vcpkg_download_distfile(ARCHIVE
            URLS "https://github.com/${ORG_NAME}/${REPO_NAME}/archive/${_vdud_REF}.tar.gz"
            SHA512 "${_vdud_SHA512}"
            FILENAME "${ORG_NAME}-${REPO_NAME}-${_vdud_REF}.tar.gz"
        )
        vcpkg_extract_source_archive_ex(ARCHIVE "${ARCHIVE}")
        set_SOURCE_PATH(${CURRENT_BUILDTREES_DIR}/src ${_vdud_REF})
        return()
    endif()

    # The following is for --head scenarios
    set(URL "https://github.com/${ORG_NAME}/${REPO_NAME}/archive/${_vdud_HEAD_REF}.tar.gz")
    set(downloaded_file_path "${DOWNLOADS}/${ORG_NAME}-${REPO_NAME}-${_vdud_HEAD_REF}.tar.gz")

    if(_VCPKG_NO_DOWNLOADS)
        if(NOT EXISTS ${downloaded_file_path} OR NOT EXISTS ${downloaded_file_path}.version)
            message(FATAL_ERROR "Downloads are disabled, but '${downloaded_file_path}' does not exist.")
        endif()
        message(STATUS "Using cached ${downloaded_file_path}")
    else()
        if(EXISTS ${downloaded_file_path})
            message(STATUS "Purging cached ${downloaded_file_path} to fetch latest (use --no-downloads to suppress)")
            file(REMOVE ${downloaded_file_path})
        endif()
        if(EXISTS ${downloaded_file_path}.version)
            file(REMOVE ${downloaded_file_path}.version)
        endif()
        if(EXISTS ${CURRENT_BUILDTREES_DIR}/src/head)
            file(REMOVE_RECURSE ${CURRENT_BUILDTREES_DIR}/src/head)
        endif()

        # Try to download the file and version information from github.
        message(STATUS "Downloading ${URL}...")
        file(DOWNLOAD "https://api.github.com/repos/${ORG_NAME}/${REPO_NAME}/git/refs/heads/${_vdud_HEAD_REF}"
            ${downloaded_file_path}.version
            STATUS download_status
        )
        list(GET download_status 0 status_code)
        if (NOT "${status_code}" STREQUAL "0")
            file(REMOVE ${downloaded_file_path}.version)
            message(FATAL_ERROR "Downloading version info for ${URL}... Failed. Status: ${download_status}")
        endif()

        file(DOWNLOAD ${URL} ${downloaded_file_path} STATUS download_status)
        list(GET download_status 0 status_code)
        if (NOT "${status_code}" STREQUAL "0")
            file(REMOVE ${downloaded_file_path})
            message(FATAL_ERROR "Downloading ${URL}... Failed. Status: ${download_status}")
        else()
            message(STATUS "Downloading ${URL}... OK")
        endif()
    endif()

    vcpkg_extract_source_archive_ex(
        ARCHIVE "${downloaded_file_path}"
        WORKING_DIRECTORY "${CURRENT_BUILDTREES_DIR}/src/head"
    )

    # Parse the github refs response with regex.
    # TODO: use some JSON swiss-army-knife utility instead.
    file(READ "${downloaded_file_path}.version" _contents)
    string(REGEX MATCH "\"sha\": \"[a-f0-9]+\"" x "${_contents}")
    string(REGEX REPLACE "\"sha\": \"([a-f0-9]+)\"" "\\1" _version ${x})

    # exports VCPKG_HEAD_VERSION to the caller. This will get picked up by ports.cmake after the build.
    set(VCPKG_HEAD_VERSION ${_version} PARENT_SCOPE)

    set_SOURCE_PATH(${CURRENT_BUILDTREES_DIR}/src/head ${_vdud_HEAD_REF})
endfunction()
