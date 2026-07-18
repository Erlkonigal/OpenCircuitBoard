cmake_minimum_required(VERSION 3.20)
project(OcbSimulation LANGUAGES CXX)

set(GODOTCPPDIR "" CACHE PATH "Path to the godot-cpp submodule")
set(OCBOUTPUTDIR "" CACHE PATH "Directory for generated OcbSimulation artifacts")

if(NOT EXISTS "${GODOTCPPDIR}/CMakeLists.txt")
	message(FATAL_ERROR "GODOTCPPDIR must point to the godot-cpp submodule.")
endif()

if(OCBOUTPUTDIR STREQUAL "")
	set(OCBOUTPUTDIR "${CMAKE_BINARY_DIR}/output")
endif()

add_subdirectory("${GODOTCPPDIR}" "${CMAKE_BINARY_DIR}/godot-cpp")
find_package(Threads REQUIRED)

set(OCB_SIMULATION_CORE_SOURCES
	src/SimulationCore.cpp
	src/GraphLocalityOrderer.cpp
)

set(OCB_HAS_GRAPH_LOCALITY_ORDERER 1)

add_library(ocbsimulation SHARED
	src/OcbSimulation.cpp
	src/RegisterTypes.cpp
	${OCB_SIMULATION_CORE_SOURCES}
)

target_compile_features(ocbsimulation PRIVATE cxx_std_17)
target_include_directories(ocbsimulation PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")
target_link_libraries(ocbsimulation PRIVATE godot::cpp Threads::Threads)

set_target_properties(ocbsimulation PROPERTIES
	PREFIX ""
	OUTPUT_NAME "ocbsimulation"
	RUNTIME_OUTPUT_DIRECTORY "${OCBOUTPUTDIR}"
	LIBRARY_OUTPUT_DIRECTORY "${OCBOUTPUTDIR}"
	ARCHIVE_OUTPUT_DIRECTORY "${OCBOUTPUTDIR}"
)

configure_file(
	"${CMAKE_CURRENT_SOURCE_DIR}/OcbSimulation.gdextension.in"
	"${CMAKE_CURRENT_SOURCE_DIR}/../OcbSimulation.gdextension"
	@ONLY
)

option(OCB_BUILD_CORE_TESTS "Build the SimulationCore unit tests" ON)
if(OCB_BUILD_CORE_TESTS)
	enable_testing()
	add_executable(ocbsimulation_core_test
		tests/SimulationCoreTests.cpp
		${OCB_SIMULATION_CORE_SOURCES}
	)
	target_compile_features(ocbsimulation_core_test PRIVATE cxx_std_17)
	target_include_directories(ocbsimulation_core_test PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")
	add_test(NAME ocbsimulation_core_test COMMAND ocbsimulation_core_test)

	add_executable(ocbsimulation_graph_locality_orderer_test
		tests/GraphLocalityOrdererTests.cpp
		src/GraphLocalityOrderer.cpp
	)
	target_compile_features(ocbsimulation_graph_locality_orderer_test PRIVATE cxx_std_17)
	target_include_directories(ocbsimulation_graph_locality_orderer_test PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")
	add_test(NAME ocbsimulation_graph_locality_orderer_test COMMAND ocbsimulation_graph_locality_orderer_test)
endif()

option(OCB_BUILD_CORE_BENCHMARK "Build the SimulationCore throughput benchmark" ON)
if(OCB_BUILD_CORE_BENCHMARK)
	add_executable(ocbsimulation_core_benchmark EXCLUDE_FROM_ALL
		tests/CoreBenchmark.cpp
		${OCB_SIMULATION_CORE_SOURCES}
	)
	target_compile_features(ocbsimulation_core_benchmark PRIVATE cxx_std_17)
	target_include_directories(ocbsimulation_core_benchmark PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")
	target_compile_definitions(ocbsimulation_core_benchmark PRIVATE OCB_HAS_GRAPH_LOCALITY_ORDERER=${OCB_HAS_GRAPH_LOCALITY_ORDERER})
endif()
