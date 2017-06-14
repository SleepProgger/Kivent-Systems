# distutils: language = c++
# cython: embedsignature=True
from kivy.properties import (
    BooleanProperty, StringProperty, NumericProperty, ListProperty, ObjectProperty
    )
from kivent_core.managers.entity_manager cimport EntityManager
from kivent_core.managers.system_manager cimport SystemManager 
from kivent_core.systems.staticmemgamesystem cimport StaticMemGameSystem, MemComponent
from kivent_core.memory_handlers.zone cimport MemoryZone
from kivent_core.memory_handlers.indexing cimport IndexedMemoryZone
from kivent_core.systems.position_systems cimport PositionStruct2D
from kivent_core.systems.rotate_systems cimport RotateStruct2D
from kivy.factory import Factory
from kivent_core.systems.position_systems cimport PositionComponent2D, PositionSystem2D
from kivent_core.systems.rotate_systems cimport RotateComponent2D, RotateSystem2D

from libc.math cimport sin, cos
from cython cimport bint
from libcpp.unordered_set cimport unordered_set
from libcpp.stack cimport stack

cdef class SocketComponent(MemComponent):
    property children:
        def __get__(self):
            cdef SocketStruct* data = <SocketStruct*>self.pointer
            return list(data.children[0])


cdef class SocketSystem(StaticMemGameSystem):
    type_size = NumericProperty(sizeof(SocketStruct))
    component_type = ObjectProperty(SocketComponent)
    updateable = BooleanProperty(False)
    processor = BooleanProperty(False)
    processor = BooleanProperty(False)
    system_names = ListProperty(['socket'])
    system_id = StringProperty('socket')
    
    def __init__(self, **kwargs):
        super(SocketSystem, self).__init__(**kwargs)
        
    def init_component(self, unsigned int component_index, 
        unsigned int entity_id, str zone, args):
        cdef MemoryZone memory_zone = self.imz_components.memory_zone
        cdef SocketStruct* pointer = <SocketStruct*>memory_zone.get_pointer(
                component_index)
        pointer.entity_id = entity_id
        pointer.children = new unordered_set[unsigned int]()
        
    def remove_component(self, unsigned int component_index):
        cdef MemoryZone socket_memory = self.imz_components.memory_zone
        cdef SocketStruct* pointer = <SocketStruct*>socket_memory.get_pointer(
            component_index)
        cdef unsigned int child_id
        gameworld = self.gameworld
        remove_entity = self.gameworld.remove_entity
        # We need to remove all children recursive, but due to recursion limit
        # we do it the iterative way.
        cdef SystemManager system_manager = gameworld.system_manager
        cdef IndexedMemoryZone entities = gameworld.entities
        cdef unsigned int socket_index = system_manager.get_system_index(
            self.system_id)
        cdef stack[SocketStruct*] child_stack
        cdef SocketStruct* cur_socket
        cdef unsigned int child_c_index
        cdef unsigned int* entity 
        child_stack.push(pointer)
        while child_stack.size() > 0:
            cur_socket = child_stack.top()
            if cur_socket.children[0].size() == 0:
                child_stack.pop()
                if cur_socket != pointer:
                    remove_entity(cur_socket.entity_id)
                continue
            for child_id in cur_socket.children[0]:
                entity = <unsigned int*>entities.get_pointer(child_id)
                child_c_index = entity[socket_index + 1]
                if child_c_index == <unsigned int>-1:
                    remove_entity(child_id)
                    continue
                cur_socket = <SocketStruct*>socket_memory.get_pointer(child_c_index)
                child_stack.push(cur_socket)
        pointer.children[0].clear()
        del pointer.children
        super(SocketSystem, self).remove_component(component_index)
        
    def clear_component(self, unsigned int component_index):
        cdef MemoryZone memory_zone = self.imz_components.memory_zone
        cdef SocketStruct* pointer = <SocketStruct*>memory_zone.get_pointer(
            component_index)
        pointer.entity_id = -1
        
Factory.register('SocketSystem', cls=SocketSystem)
        
         

cdef class AttachmentSystem2D(StaticMemGameSystem):
    '''
    Processing Depends On: PositionSystem2D, RotateSystem2D
    '''

    type_size = NumericProperty(sizeof(AttachmentStruct2D))
    component_type = ObjectProperty(AttachmentComponent2D)
    updateable = BooleanProperty(True)
    processor = BooleanProperty(True)
    do_components = BooleanProperty(True)
    system_names = ListProperty(['attachment', 'position', 'rotate'])
    system_id = StringProperty('attachment')
    
    def __init__(self, **kwargs):
        super(AttachmentSystem2D, self).__init__(**kwargs)
    
    def attach_entity(self, unsigned int entity_id, unsigned int parent_id, str zone, *args):
        return self.create_component(entity_id, zone, args)
    
    def detatch_entity(self, unsigned int entity_id):
        cdef EntityManager entity_manager = self.gameworld.entity_manager
        cdef unsigned int system_index = self.system_index
        cdef list indices = entity_manager.get_entity_entry(entity_id)
        cdef unsigned int component_index = indices[system_index]
        self.remove_component(component_index)    
    
    def init_component(self, unsigned int component_index, 
        unsigned int entity_id, str zone, dict args):
        if not 'parent' in args:
            raise ValueError("Attachment need parent entity_id.") # TODO: which exception to use ?
        cdef MemoryZone attachment_memory = self.imz_components.memory_zone
        cdef AttachmentStruct2D* pointer = <AttachmentStruct2D*>attachment_memory.get_pointer(
            component_index)
        cdef unsigned int parent_id = args['parent']
        pointer.entity_id = entity_id
        pointer.offset_x = args.get('offset_x', 0)
        pointer.offset_y = args.get('offset_y', 0)
        pointer.r = args.get('r', 0)
        # Get pointers to parent components
        cdef SystemManager system_manager = self.gameworld.system_manager
        cdef str pos_name = args.get('position_system', 'position')
        cdef str rot_name = args.get('rotate_system', 'rotate')    
        cdef str socket_name = args.get('socket_system', 'socket')
        cdef PositionSystem2D position_system = system_manager[pos_name]
        cdef RotateSystem2D rotate_system = system_manager[rot_name]
        cdef SocketSystem socket_system = system_manager[socket_name]
        cdef unsigned int pos_index = system_manager.get_system_index(
            pos_name)
        cdef unsigned int rot_index = system_manager.get_system_index(
            rot_name)
        cdef unsigned int socket_index = system_manager.get_system_index(
            socket_name)
        cdef MemoryZone pos_memory = position_system.imz_components.memory_zone
        cdef MemoryZone rot_memory = rotate_system.imz_components.memory_zone
        cdef MemoryZone socket_memory = socket_system.imz_components.memory_zone
        cdef IndexedMemoryZone entities = self.gameworld.entities
        cdef unsigned int* entity = <unsigned int*>entities.get_pointer(parent_id) 
        pointer._pos_struct = <PositionStruct2D*>pos_memory.get_pointer(
            entity[pos_index + 1])
        pointer._rot_struct = <RotateStruct2D*>rot_memory.get_pointer(
            entity[rot_index + 1])
        pointer._parent_socket = <SocketStruct*>socket_memory.get_pointer(
            entity[socket_index + 1])
        cdef unsigned int ent_comps_ind = self.entity_components.add_entity(
            entity_id, zone)
        pointer._parent_socket.children[0].insert(entity_id) 
                 
    def remove_component(self, unsigned int component_index):
        cdef MemoryZone memory_zone = self.imz_components.memory_zone
        cdef AttachmentStruct2D* pointer = <AttachmentStruct2D*>memory_zone.get_pointer(
            component_index)
        cdef unsigned int entity_id = pointer.entity_id 
        pointer._parent_socket.children[0].erase(entity_id)
        self.entity_components.remove_entity(entity_id)
        super(AttachmentSystem2D, self).remove_component(component_index) 

    def clear_component(self, unsigned int component_index):
        cdef MemoryZone memory_zone = self.imz_components.memory_zone
        cdef AttachmentStruct2D* pointer = <AttachmentStruct2D*>memory_zone.get_pointer(
            component_index)
        pointer.entity_id = -1
        pointer._pos_struct = NULL
        pointer._rot_struct = NULL
        pointer._parent_socket = NULL

    def update(self, dt):
        cdef void** component_data = <void**>(
            self.entity_components.memory_block.data)
        cdef unsigned int component_count = self.entity_components.count
        cdef unsigned int count = self.entity_components.memory_block.count
        cdef unsigned int i, real_index
        cdef AttachmentStruct2D *attachment_struct
        
        cdef PositionStruct2D *position_struct
        cdef RotateStruct2D *rotate_struct
        cdef PositionStruct2D *p_position_struct
        cdef RotateStruct2D *p_rotate_struct
        cdef float sn, cs
        
        remove_entity = self.gameworld.remove_entity
        for i in range(count):
            real_index = i*component_count
            if component_data[real_index] == NULL:
                continue            
            attachment_struct = <AttachmentStruct2D*>component_data[real_index + 0]
            if attachment_struct.entity_id == <unsigned int>-1:
                continue
            position_struct = <PositionStruct2D*>component_data[real_index + 1]
            rotate_struct = <RotateStruct2D*>component_data[real_index + 2]
            p_position_struct = attachment_struct._pos_struct
            p_rotate_struct = attachment_struct._rot_struct
            cs = cos(p_rotate_struct.r)
            sn = sin(p_rotate_struct.r)
            position_struct.x = p_position_struct.x + (attachment_struct.offset_x * cs - attachment_struct.offset_y * sn)
            position_struct.y = p_position_struct.y + (attachment_struct.offset_x * sn + attachment_struct.offset_y * cs)
            rotate_struct.r = p_rotate_struct.r + attachment_struct.r            
            
                
Factory.register('AttachmentSystem2D', cls=AttachmentSystem2D)