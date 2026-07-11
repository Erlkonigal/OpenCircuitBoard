cmake_minimum_required(VERSION 3.20)
project(OcbSimulation LANGUAGES NONE)

set(GODOTCPPDIR "" CACHE PATH "Path to the godot-cpp submodule")
set(OCBOUTPUTDIR "" CACHE PATH "Directory for generated OcbSimulation artifacts")

add_custom_target(ocbsimulation ALL)
