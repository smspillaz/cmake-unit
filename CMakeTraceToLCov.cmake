# CMakeTraceToLCov.cmake
#
# This script converts a "CMake Tracefile" (generated by passing
# -DCMAKE_UNIT_LOG_COVERAGE=ON to a cmake-unit build) into a
# Linux Test Project Coverage (LCov) file.
#
# This script assumes that it is running from the toplevel of the source
# directory
#
# Required variables:
# TRACEFILE: Path to tracefile
# LCOV_OUTPUT: Path to file to write LCov output
#
# See LICENCE.md for Copyright information.

set (TRACEFILE "" CACHE FILEPATH "Path to tracefile")
set (LCOV_OUTPUT "" CACHE FILEPATH "Path to LCov output")

if (NOT TRACEFILE)

    message (FATAL_ERROR "TRACEFILE must be specified")

endif (NOT TRACEFILE)

if (NOT LCOV_OUTPUT)

    message (FATAL_ERROR "LCOV_OUTPUT must be specified")

endif (NOT LCOV_OUTPUT)

file (READ "${TRACEFILE}" TRACEFILE_CONTENTS)
string (REPLACE "\n" ";" TRACEFILE_CONTENTS "${TRACEFILE_CONTENTS}")

# Open the file and read it for "executable lines"
# An executable line is any line that is not all whitespace or does not
# begin with a comment (#)
function (determine_executable_lines FILE)

    # First see if we've already read this file
    list (FIND _ALL_COVERAGE_FILES "${FILE}" FILE_INDEX)

    if (NOT FILE_INDEX EQUAL -1)

        return ()

    endif (NOT FILE_INDEX EQUAL -1)

    list (APPEND _ALL_COVERAGE_FILES "${FILE}")
    set (_ALL_COVERAGE_FILES "${_ALL_COVERAGE_FILES}" PARENT_SCOPE)

    file (READ "${FILE}" FILE_CONTENTS)

    # Can't have semicolons, doesn't matter what they are, just change them
    # to commas.
    string (REPLACE ";" "," FILE_CONTENTS "${FILE_CONTENTS}")

    # Convert \t to " ". Makes life easier.
    string (REPLACE "\t" " " FILE_LINES "${FILE_CONTENTS}")

    set (EXECUTABLE_LINES)

    # Tracking line regions with an opening brace but not a closed one
    # (eg call_foo (FOO
    #               BAR)) <- not executable
    set (IN_OPENED_BRACKET_REGION FALSE)

    set (LINE_COUNTER 1)
    set (NEXT_LINE_INDEX 0)
    while (NOT NEXT_LINE_INDEX EQUAL -1)

        string (SUBSTRING "${FILE_CONTENTS}" ${NEXT_LINE_INDEX} -1
                FILE_CONTENTS)
        string (FIND "${FILE_CONTENTS}" "\n" NEXT_LINE_INDEX)

        if (NOT NEXT_LINE_INDEX EQUAL -1)

            string (SUBSTRING "${FILE_CONTENTS}" 0 ${NEXT_LINE_INDEX} LINE)

            # Only lines after IN_OPENED_BRACKET_REGION is set are actually
            # disqualified. Reset all the other variables.
            set (DISQUALIFIED_DUE_TO_IN_OPEN_BRACKET_REGION
                 ${IN_OPENED_BRACKET_REGION})
            set (DISQUALIFIED_DUE_TO_MATCH FALSE)
            set (DISQUALIFIED_BECAUSE_LINE_ONLY_WHITESPACE FALSE)

            # Empty lines always disqualified
            string (STRIP "${LINE}" STRIPPED_LINE)
            if (NOT STRIPPED_LINE)

                set (DISQUALIFIED_BECAUSE_LINE_ONLY_WHITESPACE TRUE)

            endif (NOT STRIPPED_LINE)

            # The following patterns are always non-executable
            set (NON_EXECUTABLE_LINE_MATCHES
                 "^ *#" # Whitespace-before-comment
                 "^#" # Comment
                 "^end" # endfunction, endforeach, endif
                 "^ *end") # endfunction etc with whitepsace

            # Disqualify any lines matching NON_EXECUTABLE_LINE_MATCHES
            foreach (MATCH ${NON_EXECUTABLE_LINE_MATCHES})

                if ("${LINE}" MATCHES "${MATCH}")

                    set (DISQUALIFIED_DUE_TO_MATCH TRUE)
                    break ()

                endif ("${LINE}" MATCHES "${MATCH}")

            endforeach ()

            # Check if we're in an opened brace region now. We need to get a
            # version of the same line with all the comments stripped out
            string (FIND "${LINE}" "#" COMMENT_INDEX)
            if (NOT COMMENT_INDEX EQUAL -1)

                string (SUBSTRING "${LINE}" 0 ${COMMENT_INDEX}
                        LINE_WITHOUT_COMMENTS)

            else (NOT COMMENT_INDEX EQUAL -1)

                set (LINE_WITHOUT_COMMENTS "${LINE}")

            endif (NOT COMMENT_INDEX EQUAL -1)

            string (STRIP "${LINE_WITHOUT_COMMENTS}"
                    LINE_STRIPPED_WITH_NO_COMMENTS)
            string (FIND "${LINE_STRIPPED_WITH_NO_COMMENTS}" "("
                    OPEN_BRACKET_INDEX)
            string (FIND "${LINE_STRIPPED_WITH_NO_COMMENTS}" ")"
                    LAST_CLOSE_BRACKET_INDEX REVERSE)

            # Get the length of the line and the position of the last close
            # bracket index + 1. This way, if the close-bracket is the last
            # character on the stripped line, we can compare it with the
            # actual line length (last index + 1) and see if this line
            # ended with a close-bracket.
            string (LENGTH "${LINE_STRIPPED_WITH_NO_COMMENTS}" LINE_LENGTH)
            if (NOT LAST_CLOSE_BRACKET_INDEX EQUAL -1)

                math (EXPR LAST_CLOSE_BRACKET_INDEX
                      "${LAST_CLOSE_BRACKET_INDEX} + 1")

            endif (NOT LAST_CLOSE_BRACKET_INDEX EQUAL -1)

            if (IN_OPENED_BRACKET_REGION OR
                NOT OPEN_BRACKET_INDEX EQUAL -1)

                if (LAST_CLOSE_BRACKET_INDEX EQUAL LINE_LENGTH)

                    set (IN_OPENED_BRACKET_REGION FALSE)

                else (LAST_CLOSE_BRACKET_INDEX EQUAL LINE_LENGTH)

                    set (IN_OPENED_BRACKET_REGION TRUE)

                endif (LAST_CLOSE_BRACKET_INDEX EQUAL LINE_LENGTH)

            endif (IN_OPENED_BRACKET_REGION OR
                   NOT OPEN_BRACKET_INDEX EQUAL -1)

            # Finally look at the disqualifications and if none match
            # then append this line to EXECUTABLE_LINES
            if (NOT DISQUALIFIED_DUE_TO_MATCH AND
                NOT DISQUALIFIED_DUE_TO_IN_OPEN_BRACKET_REGION AND
                NOT DISQUALIFIED_BECAUSE_LINE_ONLY_WHITESPACE)

                list (APPEND EXECUTABLE_LINES ${LINE_COUNTER})

            endif (NOT DISQUALIFIED_DUE_TO_MATCH AND
                   NOT DISQUALIFIED_DUE_TO_IN_OPEN_BRACKET_REGION AND
                   NOT DISQUALIFIED_BECAUSE_LINE_ONLY_WHITESPACE)

            math (EXPR NEXT_LINE_INDEX "${NEXT_LINE_INDEX} + 1")

        endif (NOT NEXT_LINE_INDEX EQUAL -1)

        math (EXPR LINE_COUNTER "${LINE_COUNTER} + 1")

    endwhile ()

    set ("_${FILE}_EXECUTABLE_LINES" ${EXECUTABLE_LINES} PARENT_SCOPE)

endfunction ()

# Read over every line in the tracefile, skipping lines that begin with
# TEST for now, and then read off the () and the number in the braces
# and the end of the line. The remainder is the filename.
#
# Pass the filename to the executable lines scanner which will read it
# for executable lines if it hasn't been opened yet.
#
# Then create a variable called "${TRACEFILE}_HIT_${LINENO}" and store
# our updated linecount in it.
foreach (LINE ${TRACEFILE_CONTENTS})

    if ("${LINE}" MATCHES "FILE.*$")

        # Get the filename
        string (LENGTH "FILE:" HEADER_LENGTH)
        string (SUBSTRING "${LINE}" ${HEADER_LENGTH} -1 FILEPATH)
        determine_executable_lines ("${FILEPATH}")

    endif ("${LINE}" MATCHES "FILE.*$")

    if (NOT "${LINE}" MATCHES "TEST.*$" AND
        NOT "${LINE}" MATCHES "FILE.*$")

        # Find our brackets
        string (FIND "${LINE}" ")" LAST_BRACKET REVERSE)
        string (FIND "${LINE}" "(" FIRST_BRACKET REVERSE)

        # Get the filename
        string (SUBSTRING "${LINE}" 0 ${FIRST_BRACKET} FILEPATH)

        # Now get a substring in between the brackets
        math (EXPR FIRST_NUMBER "${FIRST_BRACKET} + 1")
        math (EXPR LINENO_LENGTH "${LAST_BRACKET} - ${FIRST_NUMBER}")
        string (SUBSTRING "${LINE}" ${FIRST_NUMBER} ${LINENO_LENGTH}
                LINENO)

        set (HIT_VARIABLE "_${FILEPATH}_HIT_${LINENO}")

        if (NOT "${${HIT_VARIABLE}}")

            set ("${HIT_VARIABLE}" 0)

        endif (NOT "${${HIT_VARIABLE}}")

        math (EXPR "${HIT_VARIABLE}" "${${HIT_VARIABLE}} + 1")

    endif (NOT "${LINE}" MATCHES "TEST.*$" AND
           NOT "${LINE}" MATCHES "FILE.*$")

endforeach ()

# Now for each file that was read, write out its line hit entries in our
# tracefile
foreach (FILE ${_ALL_COVERAGE_FILES})

    # Find the relative path - this allows us to run
    # CMakeTraceToLCov from the top of the source directory and get
    # relative paths, which is useful for online tools like coveralls
    string (LENGTH "${CMAKE_CURRENT_SOURCE_DIR}/" SOURCE_DIR_PATH_LENGTH)
    string (SUBSTRING "${FILE}" ${SOURCE_DIR_PATH_LENGTH} -1
            RELATIVE_PATH_TO_FILE)

    if (NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/${RELATIVE_PATH_TO_FILE}")

        message (FATAL_ERROR "Couldn't find ${RELATIVE_PATH_TO_FILE} relative "
                             " to ${CMAKE_CURRENT_SOURCE_DIR}. Are you running "
                             " this script from the toplevel source directory?")

    endif (NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/${RELATIVE_PATH_TO_FILE}")

    list (APPEND LCOV_OUTPUT_CONTENTS
          "SF:${RELATIVE_PATH_TO_FILE}\n")

    set (NUMBER_OF_LINES_WITH_POSITIVE_HIT_COUNTS 0)
    list (LENGTH "_${FILE}_EXECUTABLE_LINES" NUMBER_OF_EXECUTABLE_LINES)

    # SOURCE_FILE_HITS will be appended to the file later, prevent lots of
    # calls to fwrite
    set (SOURCE_FILE_HITS)
    foreach (EXECUTABLE_LINE ${_${FILE}_EXECUTABLE_LINES})

        set (HIT_VARIABLE _${FILE}_HIT_${EXECUTABLE_LINE})
        if (NOT "${${HIT_VARIABLE}}")

            list (APPEND SOURCE_FILE_HITS
                  "DA:${EXECUTABLE_LINE},0")

        else (NOT "${${HIT_VARIABLE}}")

            list (APPEND SOURCE_FILE_HITS
                  "DA:${EXECUTABLE_LINE},${${HIT_VARIABLE}}")
            math (EXPR NUMBER_OF_LINES_WITH_POSITIVE_HIT_COUNTS
                  "${NUMBER_OF_LINES_WITH_POSITIVE_HIT_COUNTS} + 1")

        endif (NOT "${${HIT_VARIABLE}}")

    endforeach ()

    string (REPLACE ";" "\n" SOURCE_FILE_HITS "${SOURCE_FILE_HITS}")
    list (APPEND LCOV_OUTPUT_CONTENTS
          "${SOURCE_FILE_HITS}\n"
          "LH:${NUMBER_OF_LINES_WITH_POSITIVE_HIT_COUNTS}\n"
          "LF:${NUMBER_OF_EXECUTABLE_LINES}\n"
          "end_of_record\n\n")

endforeach ()

# Write out LCOV_OUTPUT just by writing entire list
file (WRITE "${LCOV_OUTPUT}" ${LCOV_OUTPUT_CONTENTS})