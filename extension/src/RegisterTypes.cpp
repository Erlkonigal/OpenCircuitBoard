#include "OcbSimulation.hpp"

#include <gdextension_interface.h>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

namespace ocb {

void initializeOcbSimulation(godot::ModuleInitializationLevel level) {
	if (level != godot::MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(OcbSimulation);
}

void uninitializeOcbSimulation(godot::ModuleInitializationLevel level) {
	if (level != godot::MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
}

} // namespace ocb

extern "C" {

GDExtensionBool GDE_EXPORT ocbLibraryInit(
		GDExtensionInterfaceGetProcAddress getProcAddress,
		GDExtensionClassLibraryPtr library,
		GDExtensionInitialization *initialization) {
	godot::GDExtensionBinding::InitObject initObject(getProcAddress, library, initialization);
	initObject.register_initializer(ocb::initializeOcbSimulation);
	initObject.register_terminator(ocb::uninitializeOcbSimulation);
	initObject.set_minimum_library_initialization_level(godot::MODULE_INITIALIZATION_LEVEL_SCENE);
	return initObject.init();
}

}
