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


cdef class RelationComponent(MemComponent):
    '''
    The RelationComponent holds a list of all entities attached to the
    entity holding this component.
    
    Its main use is to automatically remove all attached entities
    when the entity is removed from the gameworld and to iterate
    relationsship trees.

    **Attributes:**
        **entity_id** (unsigned int): The entity_id this component is currently
        associated with. Will be <unsigned int>-1 if the component is
        unattached.
        
        **parent** (unsigned int): The id of the parent or <unsigned int>-1
        if this element doesn't have a parent.        

        **children** (list): A list of all entity_ids of the attached entities.
    '''
    property entity_id:
        def __get__(self):
            cdef RelationStruct* data = <RelationStruct*>self.pointer
            return data.entity_id
        
    property parent:
        def __get__(self):
            cdef RelationStruct* data = <RelationStruct*>self.pointer
            if data.parent == NULL:
                return <unsigned int>-1
            return data.parent.entity_id
        
    property children:
        def __get__(self):
            cdef RelationStruct* data = <RelationStruct*>self.pointer
            if data.children == NULL:
                return 0
            return list(x.entity_id for x in data.children[0])


cdef class RelationSystem(StaticMemGameSystem):
    '''
    Processing Depends only on itself.
    
    A flexible Relationship system which can be used by different GameSystems
    which need to attach entities to others in one way or another.
    Currently it is only used by the AttachmentSystem2D.
    
    Attached childrens are automatically removed when the parent
    is removed.
    
    For entities with a relationsship AND attachment component the socket component
    need to be initialized BEFORE the attachment.
    
    **Attributes: (Cython Access Only):
        **root_nodes** (unordered_set[RelationStruct*]): All sockets which
        aren't itself children of other sockets.
        It is usefull if you want to iterate over the attachment tree
        from top to bottom (see AttachmentSystem2D for an example).
    '''
    type_size = NumericProperty(sizeof(RelationStruct))
    component_type = ObjectProperty(RelationComponent)
    updateable = BooleanProperty(False)
    processor = BooleanProperty(False)
    system_names = ListProperty(['relations'])
    system_id = StringProperty('relations')
    
    def __init__(self, **kwargs):
        super(RelationSystem, self).__init__(**kwargs)
        
    def init_component(self, unsigned int component_index, 
        unsigned int entity_id, str zone, args):
        cdef MemoryZone memory_zone = self.imz_components.memory_zone
        cdef RelationStruct* pointer = <RelationStruct*>memory_zone.get_pointer(
                component_index)
        pointer.entity_id = entity_id
        pointer.parent = NULL
        pointer.children = NULL
        self.root_nodes.insert(pointer)
    
    cdef _attach_child(self, RelationStruct* parent, RelationStruct* child):
        '''
        Register a child as attachment of the parent_socket.
        Should only be used from AttachmentSystems init_component method.        
        
        **Parameter:
            **parent** (RelationStruct*)
            
            **child** (RelationStruct*)
        '''
        child.parent = parent
        if parent.children == NULL:
            parent.children = new cpp_set[RelationStruct*]()
        parent.children[0].insert(child)
        self.root_nodes.erase(child)
            
    cdef _detach_child(self, RelationStruct* child):
        '''
        Deregister an attachment.
        Should only be used from AttachmentSystems remove_component method.        
        
        **Parameter:
            **parent_socket** (RelationStruct*)
            
            **child_id** (unsigned int): The entity_id of the child to attach.
        '''
        child.parent.children[0].erase(child)
        self.root_nodes.insert(child)
        child.parent = NULL
        
    cdef _detach_child_by_id(self, unsigned int child_id):
        cdef MemoryZone my_memory = self.imz_components.memory_zone
        cdef IndexedMemoryZone entities = self.gameworld.entities
        cdef unsigned int system_index = self.system_index + 1
        cdef unsigned int* entity = <unsigned int*>entities.get_pointer(child_id)
        cdef RelationStruct *child_struct = <RelationStruct*>my_memory.get_pointer(
            entity[system_index])
        self._detach_child(child_struct)
        
    def remove_component(self, unsigned int component_index):
        cdef MemoryZone socket_memory = self.imz_components.memory_zone
        cdef RelationStruct* pointer = <RelationStruct*>socket_memory.get_pointer(
            component_index)
        cdef unsigned int child_id
        cdef RelationStruct* cur_socket
        cdef RelationStruct* child_socket
        gameworld = self.gameworld
        remove_entity = self.gameworld.remove_entity
        # We need to remove all children recursive, but due to recursion limit
        # we replace the recursion with a stack based approach.
        cdef stack[RelationStruct*] child_stack = self._child_stack
        child_stack.push(pointer)
        while child_stack.size() > 0:
            cur_socket = child_stack.top()
            if cur_socket.children == NULL or cur_socket.children[0].size() == 0:
                child_stack.pop()
                if cur_socket != pointer:
                    remove_entity(cur_socket.entity_id)
                continue
            if cur_socket.children:
                for child_socket in cur_socket.children[0]:
                    child_stack.push(child_socket)
        if pointer.children:
            pointer.children[0].clear()
            del pointer.children
        self.root_nodes.erase(pointer)
        super(RelationSystem, self).remove_component(component_index)
        
    def clear_component(self, unsigned int component_index):
        cdef MemoryZone memory_zone = self.imz_components.memory_zone
        cdef RelationStruct* pointer = <RelationStruct*>memory_zone.get_pointer(
            component_index)
        pointer.entity_id = -1
        pointer.parent = NULL
        
Factory.register('RelationSystem', cls=RelationSystem)
        
        
cdef class AttachmentComponent2D(MemComponent):
    '''
    The AttachmentComponent2D is associated with the AttachmentSystem2D.
    It holds the offset and rotation relative to the parent entity.

    **Attributes:**
        **entity_id** (unsigned int): The entity_id this component is currently
        associated with. Will be <unsigned int>-1 if the component is
        unattached.

        **parent_id** (unsigned int): The entity_id of the parent entity.
        
        **offset_x** (float): The x offset relative to the parent.
        
        **offset_y** (float): The y offset relative to the parent.
        
        **offset** (tuple): The offset (x,y) relative to the parent as tuple.
        
        **r** (float): The rotation relative to the parent.
    '''
    property entity_id:
        def __get__(self):
            cdef AttachmentStruct2D* data = <AttachmentStruct2D*>self.pointer
            return data.entity_id
        
    property parent_id:
        def __get__(self):
            cdef AttachmentStruct2D* data = <AttachmentStruct2D*>self.pointer
            return data._pos_struct.entity_id
        
    property offset_x:
        def __get__(self):
            cdef AttachmentStruct2D* data = <AttachmentStruct2D*>self.pointer
            return data.offset_x
        def __set__(self, float value):
            cdef AttachmentStruct2D* data = <AttachmentStruct2D*>self.pointer
            data.offset_x = value
            
    property offset_y:
        def __get__(self):
            cdef AttachmentStruct2D* data = <AttachmentStruct2D*>self.pointer
            return data.offset_y
        def __set__(self, float value):
            cdef AttachmentStruct2D* data = <AttachmentStruct2D*>self.pointer
            data.offset_y = value
            
    property r:
        def __get__(self):
            cdef AttachmentStruct2D* data = <AttachmentStruct2D*>self.pointer
            return data.r
        def __set__(self, float value):
            cdef AttachmentStruct2D* data = <AttachmentStruct2D*>self.pointer
            data.r = value
            
    property offset:
        def __get__(self):
            cdef AttachmentStruct2D* data = <AttachmentStruct2D*>self.pointer
            return (data.offset_x, data.offset_y)
        def __set__(self, tuple value):
            if len(value) != 2:
                raise ValueError("AttachmentComponent2D.offset need to be a tuple of 2 elements.")
            cdef AttachmentStruct2D* data = <AttachmentStruct2D*>self.pointer
            data.offset_x = value[0]
            data.offset_y = value[1]


cdef class AttachmentSystem2D(StaticMemGameSystem):
    '''
    Processing Depends On: AttachmentSystem2D, PositionSystem2D, RotateSystem2D,
    RelationSystem

    The AttachmentSystem2D allows to attach entities to other entities to 
    construct local coordinate systems.
    Attached entities and their parents need to own a RelationComponent.

    Local coordinates (offset) and local rotation (r) are available.

    Entities which act as parent AND childof another entity need to initialize
    the RelationComponent before the AttachmentComponent.
    '''
    type_size = NumericProperty(sizeof(AttachmentStruct2D))
    component_type = ObjectProperty(AttachmentComponent2D)
    updateable = BooleanProperty(True)
    processor = BooleanProperty(True)
    system_names = ListProperty(['attachment', 'relations', 'position', 'rotate'])
    system_id = StringProperty('attachment')
    
    def __init__(self, **kwargs):
        super(AttachmentSystem2D, self).__init__(**kwargs)
    
    def attach_entity(self, unsigned int entity_id, str zone, **kwargs):
        return self.create_component(entity_id, zone, kwargs)
    
    def detatch_entity(self, unsigned int entity_id):
        cdef unsigned int system_index = self.system_index
        cdef IndexedMemoryZone entities = self.gameworld.entities
        cdef unsigned int *entity = <unsigned int*>entities.get_pointer(entity_id)
        self.remove_component( entity[system_index + 1] )    
    
    def init_component(self, unsigned int component_index, 
        unsigned int entity_id, str zone, dict args):
        if not 'parent' in args:
            raise ValueError("Attachment need parent entity_id.")
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
        cdef str socket_name = self.system_names[1]
        cdef PositionSystem2D position_system = system_manager[pos_name]
        cdef RotateSystem2D rotate_system = system_manager[rot_name]
        cdef RelationSystem socket_system = system_manager[socket_name]
        cdef unsigned int pos_index = system_manager.get_system_index(
            pos_name) + 1
        cdef unsigned int rot_index = system_manager.get_system_index(
            rot_name) + 1
        cdef unsigned int socket_index = system_manager.get_system_index(
            socket_name) + 1
        cdef MemoryZone pos_memory = position_system.imz_components.memory_zone
        cdef MemoryZone rot_memory = rotate_system.imz_components.memory_zone
        cdef MemoryZone socket_memory = socket_system.imz_components.memory_zone
        cdef IndexedMemoryZone entities = self.gameworld.entities
        cdef unsigned int* entity = <unsigned int*>entities.get_pointer(parent_id)
        if (entity[pos_index] == <unsigned int>-1
                or entity[rot_index] == <unsigned int>-1
                or entity[socket_index] == <unsigned int>-1):
            raise ValueError("AttachmentSystem2D: Invalid parent entity.")
        cdef RelationStruct *parent_struct = <RelationStruct*>socket_memory.get_pointer(
            entity[socket_index])
        if parent_struct.entity_id == <unsigned int>-1:
            raise ValueError("AttachmentSystem2D: Parent not initialized.")            
        pointer._pos_struct = <PositionStruct2D*>pos_memory.get_pointer(
            entity[pos_index])
        pointer._rot_struct = <RotateStruct2D*>rot_memory.get_pointer(
            entity[rot_index])
        # Get my own RelationStruct
        cdef unsigned int ent_comps_ind = self.entity_components.add_entity(
            entity_id, zone)
        cdef unsigned int component_count = self.entity_components.count
        cdef void** component_data = <void**>(
            self.entity_components.memory_block.data)
        cdef RelationStruct *my_socket = <RelationStruct*>component_data[
            component_count * ent_comps_ind + 1]
        # Store our components_id to easily look up the components
        # in the update method.
        my_socket.user_data = ent_comps_ind
        socket_system._attach_child(parent_struct, my_socket)
                 
    def remove_component(self, unsigned int component_index):
        cdef SystemManager system_manager = self.gameworld.system_manager
        cdef RelationSystem socket_system = system_manager[self.system_names[1]] 
        cdef MemoryZone memory_zone = self.imz_components.memory_zone
        cdef AttachmentStruct2D* pointer = <AttachmentStruct2D*>memory_zone.get_pointer(
            component_index)
        cdef unsigned int entity_id = pointer.entity_id
        socket_system._detach_child_by_id(entity_id)
        self.entity_components.remove_entity(entity_id)
        super(AttachmentSystem2D, self).remove_component(component_index) 

    def clear_component(self, unsigned int component_index):
        cdef MemoryZone memory_zone = self.imz_components.memory_zone
        cdef AttachmentStruct2D* pointer = <AttachmentStruct2D*>memory_zone.get_pointer(
            component_index)
        pointer.entity_id = -1
        pointer._pos_struct = NULL
        pointer._rot_struct = NULL

    def update(self, dt):
        cdef unsigned int component_count = self.entity_components.count
        cdef max_comp_index = self.entity_components.memory_block.count - 1
        cdef void** component_data = <void**>(
            self.entity_components.memory_block.data)
        cdef SystemManager system_manager = self.gameworld.system_manager
        cdef RelationSystem socket_system = system_manager[self.system_names[1]]
        cdef unsigned int user_data, real_index
        cdef RelationStruct *parent
        cdef RelationStruct *child
        cdef float sn, cs
        cdef AttachmentStruct2D *attachment_struct
        cdef PositionStruct2D *position_struct
        cdef RotateStruct2D *rotate_struct
        cdef PositionStruct2D *p_position_struct
        cdef RotateStruct2D *p_rotate_struct        
        # We need to update the values in the correct order.
        # Init with all root nodes.
        cdef cpp_queue[RelationStruct*] work_queue = self._work_queue
        for parent in socket_system.root_nodes:
            if parent.children == NULL:
                continue
            for child in parent.children[0]:
                work_queue.push(child)
        while not work_queue.empty():
            parent = work_queue.front()
            user_data = parent.user_data 
            work_queue.pop()
            if parent.children and parent.children[0].size():
                for child in parent.children[0]:
                    work_queue.push(child)
            # We need to skip sockets not part of this attachment system.
            if user_data > max_comp_index:
                continue
            real_index = user_data * component_count
            attachment_struct = <AttachmentStruct2D*>component_data[real_index + 0]
            if attachment_struct.entity_id != parent.entity_id:
                continue
            # Calculate the new position and rotation
            position_struct = <PositionStruct2D*>component_data[real_index + 2]
            rotate_struct = <RotateStruct2D*>component_data[real_index + 3]
            p_position_struct = attachment_struct._pos_struct
            p_rotate_struct = attachment_struct._rot_struct
            cs = cos(p_rotate_struct.r)
            sn = sin(p_rotate_struct.r)
            position_struct.x = p_position_struct.x + (
                attachment_struct.offset_x * cs - attachment_struct.offset_y * sn)
            position_struct.y = p_position_struct.y + (
                attachment_struct.offset_x * sn + attachment_struct.offset_y * cs)
            rotate_struct.r = p_rotate_struct.r + attachment_struct.r
        
Factory.register('AttachmentSystem2D', cls=AttachmentSystem2D)