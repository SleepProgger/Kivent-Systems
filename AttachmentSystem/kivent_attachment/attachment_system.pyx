# distutils: language = c++
# cython: embedsignature=True
from kivy.properties import (
    BooleanProperty, StringProperty, NumericProperty, ListProperty, ObjectProperty
    )
from kivent_core.managers.entity_manager cimport EntityManager
from kivent_core.managers.system_manager cimport SystemManager 
from kivent_core.systems.staticmemgamesystem cimport StaticMemGameSystem, MemComponent
from kivent_core.memory_handlers.zone cimport MemoryZone
from kivent_core.memory_handlers.membuffer cimport Buffer
from kivent_core.memory_handlers.indexing cimport IndexedMemoryZone
from kivent_core.systems.position_systems cimport PositionStruct2D
from kivent_core.systems.rotate_systems cimport RotateStruct2D
from kivy.factory import Factory
from kivent_core.systems.position_systems cimport PositionComponent2D, PositionSystem2D
from kivent_core.systems.rotate_systems cimport RotateComponent2D, RotateSystem2D
from kivent_core.systems.gamesystem cimport GameSystem 
from libc.math cimport sin, cos


cdef class RelationComponent(MemComponent):
    '''
    The RelationComponent holds a list of all entities attached to the
    entity holding this component.
    
    Its main use is to iterate over RelationTrees.

    **Attributes:**
        **entity_id** (unsigned int): The entity_id this component is currently
        associated with. Will be <unsigned int>-1 if the component is
        unattached.
        
        **parent** (unsigned int): The id of the parent or <unsigned int>-1
        if this element doesn't have a parent.        

        **children** (list): A list of all entity_ids of the child entities.
        
        **is_root** (bool): True if this component has a parent.
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
                return []
            return list(x.entity_id for x in data.children[0])
        
    property is_root:
        def __get__(self):
            cdef RelationStruct* data = <RelationStruct*>self.pointer
            return data.parent == NULL

cdef class RelationTreeSystem(StaticMemGameSystem):
    '''
    Processing Depends only on itself.
    
    A flexible Relationship system which can be used by different GameSystems
    which need to attach entities to others in one way or another.
    Currently its main use is create local coordinate systems.
    
    When removing a parent component all childs are detached
    and changed to root nodes.
    If you want to remove a parent and its childs use the remove_subtree method.
    
    **Attributes: (Cython Access Only):
        **root_nodes** (unordered_set[RelationStruct*]): All sockets which
        aren't itself children of other sockets.
        It is usefull if you want to iterate over the attachment tree
        from top to bottom (see AttachmentSystem2D for an example).
        
        **_state** (unsigned int): A simple (wrap around) counter which is
        increased after every change to the relationsship tree.
        Usefull to check if the tree has changed since the last update tick
        when the iteration order is cached.
    '''
    type_size = NumericProperty(sizeof(RelationStruct))
    component_type = ObjectProperty(RelationComponent)
    updateable = BooleanProperty(False)
    processor = BooleanProperty(False)
    system_names = ListProperty(['relations'])
    system_id = StringProperty('relations')
    
    def __init__(self, **kwargs):
        super(RelationTreeSystem, self).__init__(**kwargs)
        self._state = 0
        
    def init_component(self, unsigned int component_index, 
        unsigned int entity_id, str zone, args):
        cdef MemoryZone memory_zone = self.imz_components.memory_zone
        cdef RelationStruct* pointer = <RelationStruct*>memory_zone.get_pointer(
                component_index)
        pointer.entity_id = entity_id
        pointer.children = NULL
        pointer.parent = NULL
        self.root_nodes.insert(pointer)
    
    cdef RelationStruct* _attach_child(self, RelationStruct* parent, RelationStruct* child) except NULL:
        '''
        Register a child as attachment of a parent.        
        
        **Parameter:
            **parent** (RelationStruct*)
            
            **child** (RelationStruct*)
        '''
        if child.parent != NULL:
            self._detach_child(child)
        child.parent = parent
        if parent.children == NULL:
            parent.children = new cpp_set[RelationStruct*]()
        parent.children[0].insert(child)
        self.root_nodes.erase(child)
        self._state = (self._state + 1) % <unsigned int>-1
        return child
        
    cdef RelationStruct* _attach_child_by_id(self, unsigned int parent_id, unsigned int child_id) except NULL:
        cdef MemoryZone my_memory = self.imz_components.memory_zone
        cdef IndexedMemoryZone entities = self.gameworld.entities
        cdef unsigned int system_index = self.system_index + 1
        cdef unsigned int* entity = <unsigned int*>entities.get_pointer(child_id)
        cdef RelationStruct *child_struct = <RelationStruct*>my_memory.get_pointer(
            entity[system_index])
        entity = <unsigned int*>entities.get_pointer(parent_id)
        cdef RelationStruct *parent_struct = <RelationStruct*>my_memory.get_pointer(
            entity[system_index])
        return self._attach_child(parent_struct, child_struct)
    
    cdef unsigned int _detach_child(self, RelationStruct* child) except 0:
        '''
        Deregister an attachment.
        The child will be changed to a root node.        
        
        **Parameter:
            **child** (RelationStruct*)
        '''
        if child.parent == NULL or child.parent.children == NULL:
            raise ValueError("Can't detach entities without parent.") # TODO: correct exception
        child.parent.children[0].erase(child)
        self.root_nodes.insert(child)
        child.parent = NULL
        self._state = (self._state + 1) % <unsigned int>-1
        return 1
        
    cdef unsigned int _detach_child_by_id(self, unsigned int child_id) except 0:
        cdef MemoryZone my_memory = self.imz_components.memory_zone
        cdef IndexedMemoryZone entities = self.gameworld.entities
        cdef unsigned int system_index = self.system_index + 1
        cdef unsigned int* entity = <unsigned int*>entities.get_pointer(child_id)
        cdef RelationStruct *child_struct = <RelationStruct*>my_memory.get_pointer(
            entity[system_index])
        return self._detach_child(child_struct)
        
    def remove_component(self, unsigned int component_index):
        cdef MemoryZone socket_memory = self.imz_components.memory_zone
        cdef RelationStruct* pointer = <RelationStruct*>socket_memory.get_pointer(
            component_index)
        cdef RelationStruct* child
        if pointer.parent:
            pointer.parent.children[0].erase(pointer)
        if pointer.children:
            for child in pointer.children[0]:
                self._detach_child(child)
            pointer.children[0].clear()
            del pointer.children
        self.root_nodes.erase(pointer)
        self._state = (self._state + 1) % <unsigned int>-1                 
        super(RelationTreeSystem, self).remove_component(component_index)
        
    def clear_component(self, unsigned int component_index):
        cdef MemoryZone memory_zone = self.imz_components.memory_zone
        cdef RelationStruct* pointer = <RelationStruct*>memory_zone.get_pointer(
            component_index)
        pointer.entity_id = -1
        pointer.parent = NULL
        pointer.components_index = -1
        
    cdef unsigned int get_topdown_iterator(self, vector[RelationStruct*] *output) except -1:
        """
        Fills the output vector with all non root nodes in a top down fashion.
        """
        cdef RelationStruct *parent
        cdef RelationStruct *child
        cdef unsigned int size, pos
        size = pos = 0
        output[0].clear()
        for parent in self.root_nodes:
            if parent.children == NULL:
                continue
            for child in parent.children[0]:
                output[0].push_back(child)
                size += 1
        while pos < size:
            parent = output[0][pos] 
            if parent.children and parent.children[0].size():
                for child in parent.children[0]:
                    output[0].push_back(child)
                    size += 1
            pos += 1
        return size
        
    def attach_child(self, unsigned int parent_id, unsigned int child_id):
        self._attach_child_by_id(parent_id, child_id)
        
    def detach_child(self, unsigned int child_id):
        self._detach_child_by_id(child_id)
        
    def remove_subtree(self, unsigned int entity_id):
        gameworld = self.gameworld
        remove_entity = gameworld.remove_entity
        cdef MemoryZone my_memory = self.imz_components.memory_zone
        cdef IndexedMemoryZone entities = gameworld.entities
        cdef unsigned int system_index = self.system_index + 1
        cdef unsigned int* entity = <unsigned int*>entities.get_pointer(entity_id)
        if entity[system_index] == <unsigned int>-1:
            raise ValueError('Entity has no %s component' % self.system_name)
        cdef RelationStruct *pointer = <RelationStruct*>my_memory.get_pointer(
            entity[system_index])
        cdef RelationStruct* cur_parent
        cdef RelationStruct* cur_child
        # We need to remove all children recursive, but due to recursion limit
        # we replace the recursion with a stack based approach.
        cdef stack[RelationStruct*] child_stack
        child_stack.push(pointer)
        while not child_stack.empty():
            cur_parent = child_stack.top()
            if cur_parent.children == NULL or cur_parent.children[0].size() == 0:
                child_stack.pop()
                if cur_parent != pointer:
                    remove_entity(cur_parent.entity_id)
                continue
            if cur_parent.children != NULL:
                for cur_child in cur_parent.children[0]:
                    child_stack.push(cur_child)
        remove_entity(pointer.entity_id)
        self._state = (self._state + 1) % <unsigned int>-1 
        
Factory.register('RelationTreeSystem', cls=RelationTreeSystem)


cdef class LocalPositionSystem2D(RelationTreeSystem):
    '''
    Processing Depends On: LocalPositionSystem2D, PositionSystem2D

    The LocalPositionSystem2D allows to attach entities to other entities to 
    construct local coordinate systems.
    Local coordinates (offset) are available.
    
    Root nodes also need to own the local position component
    even if they aren't used.
    '''   
    updateable = BooleanProperty(True)
    processor = BooleanProperty(True)    
    # own components global position
    system_names = ListProperty([
        'position'
    ])
    local_systems = ListProperty([
        'local_position'
    ])
    parent_systems = ListProperty([
        'position'
    ])
    system_id = StringProperty('local_position_system')
    
    def __init__(self, **kwargs):
        self._parent_offset = len(self.system_names) + len(self.local_systems)
        self._last_socket_state = 0
        self._allocated = 0
        super(LocalPositionSystem2D, self).__init__(**kwargs)
        
    def allocate(self, Buffer master_buffer, dict reserve_spec):
        # We use our own component as placeholder for the parent components
        # because we might not have the related parent components.
        cdef str my_component = self.system_names[0]
        self.system_names = list(self.system_names + self.local_systems +
                              list(my_component for _ in self.parent_systems))
        self._allocated = 1
        return super(LocalPositionSystem2D, self).allocate(master_buffer, reserve_spec)

    def on_parent_systems(self, _, v):
        if self._allocated:
            # TODO: use correct exceptions
            raise ValueError("Can't change 'parent_systems' after system allocation.")
        self.parent_systems = list(v)
    def on_local_systems(self, _, v):
        if self._allocated:
            # TODO: use correct exceptions
            raise ValueError("Can't change 'local_systems' after system allocation.")
        self.local_systems = list(v)
    def on_system_names(self, _, v):
        if self._allocated:
            # TODO: use correct exceptions
            raise ValueError("Can't change 'system_names' after system allocation.")
        self.system_names = list(v)
    
    cdef unsigned int _init_component(self, unsigned entity_id,
                    unsigned int component_index,
                    unsigned int components_index,
                    RelationStruct *relation_struct) except 0:
        '''
        Overwrite this method if you want to set the user_data.
        You can safely store pointer in the user_data field.
        '''
        return 1
    
    def init_component(self, unsigned int component_index, 
        unsigned int entity_id, str zone, dict args):
        super(LocalPositionSystem2D, self).init_component(
            component_index, entity_id, zone, args)
        cdef MemoryZone memory_zone = self.imz_components.memory_zone
        cdef RelationStruct *relation_struct = <RelationStruct *>memory_zone.get_pointer(
            component_index)
        cdef unsigned int ent_comps_ind = self.entity_components.add_entity(
            entity_id, zone)
        relation_struct.components_index = ent_comps_ind        
        if not 'parent' in args or args['parent'] == -1:
            return
        cdef unsigned int parent_id = args['parent']
        self._attach_child_by_id(parent_id, entity_id)
        self._init_component(entity_id, component_index,
                             ent_comps_ind, relation_struct)
                 
    def remove_component(self, unsigned int component_index):
        cdef MemoryZone memory_zone = self.imz_components.memory_zone
        cdef RelationStruct *pointer = <RelationStruct *>memory_zone.get_pointer(
            component_index)
        self.entity_components.remove_entity(pointer.components_index)
        super(LocalPositionSystem2D, self).remove_component(component_index)
        
    cdef RelationStruct* _attach_child(self, RelationStruct* parent, RelationStruct* child) except NULL:
        RelationTreeSystem._attach_child(self, parent, child)
        # We need to set or update the parent component pointer
        cdef SystemManager system_manager = self.gameworld.system_manager
        cdef IndexedMemoryZone entities = self.gameworld.entities
        cdef unsigned int *parent_entity = <unsigned int*>entities.get_pointer(
            parent.entity_id)
        cdef unsigned int ent_comp_index = child.components_index
        cdef str system_name
        cdef unsigned int system_index
        cdef StaticMemGameSystem system        
        cdef MemoryZone system_memory
        cdef unsigned int comp_index
        cdef void *pointer
        cdef unsigned int component_count = self.entity_components.count
        cdef void** component_data = <void**>(
            self.entity_components.memory_block.data)
        cdef real_index = ent_comp_index * component_count
        cdef unsigned int i = self._parent_offset
        for system_name in self.parent_systems:
            system = system_manager[system_name]
            system_index = system.system_index + 1
            comp_index = parent_entity[system_index]
            if comp_index == <unsigned int>-1:
                raise ValueError("Attachments parent has no '%s' component." % system_name)
            system_memory = system.imz_components.memory_zone
            pointer = system_memory.get_pointer(comp_index)
            component_data[real_index + i] = pointer
            i += 1
        return child

    cdef unsigned int _update(self, float dt, vector[RelationStruct*] *work_queue) except 0:
        cdef void** component_data = <void**>(
            self.entity_components.memory_block.data)
        cdef unsigned int component_count = self.entity_components.count
        cdef PositionStruct2D *global_pos 
        cdef PositionStruct2D *local_pos 
        cdef PositionStruct2D *parent_pos
        cdef RelationStruct *parent
        cdef unsigned int real_index
        for parent in work_queue[0]:
            if parent == NULL:
                continue
            real_index = parent.components_index * component_count
            global_pos = <PositionStruct2D*>component_data[real_index + 0]
            local_pos = <PositionStruct2D*>component_data[real_index + 1]
            parent_pos = <PositionStruct2D*>component_data[real_index + 2]
            global_pos.x = parent_pos.x + local_pos.x
            global_pos.y = parent_pos.y + local_pos.y
        return 1

    def update(self, dt):
        # We need to update the values in the correct order.
        # TODO: switch to static memory
        cdef vector[RelationStruct*] *work_queue = &self._work_queue
        if self._state != self._last_socket_state:
            self.get_topdown_iterator(work_queue)
            self._last_socket_state = self._state
        # Do the real calculations
        self._update(dt, work_queue)
    
Factory.register('LocalPositionSystem2D', cls=LocalPositionSystem2D)


cdef class LocalPositionRotateSystem2D(LocalPositionSystem2D):
    """
    Processing Depends On: LocalPositionRotateSystem2D, PositionSystem2D,
    RotateSystem2D

    The LocalPositionSystem2D allows to attach entities to other entities to 
    construct local coordinate systems.
    Local coordinates (offset) and local rotation are available.
    
    Root nodes also need to own the local position and local rotation
    components even if they aren't used.
    """
    # own components global position
    system_names = ListProperty([
        'position', 'rotate'
    ])
    local_systems = ListProperty([
        'local_position', 'local_rotate'
    ])
    parent_systems = ListProperty([
        'position', 'rotate'
    ])
    system_id = StringProperty('local_position_rotate_system')
    
    cdef unsigned int _update(self, float dt, vector[RelationStruct*] *work_queue) except 0:
        cdef void** component_data = <void**>(
            self.entity_components.memory_block.data)
        cdef unsigned int component_count = self.entity_components.count
        cdef PositionStruct2D *global_pos 
        cdef PositionStruct2D *local_pos 
        cdef PositionStruct2D *parent_pos
        cdef RotateStruct2D *global_rot
        cdef RotateStruct2D *local_rot
        cdef RotateStruct2D *parent_rot
        cdef RelationStruct *parent
        cdef unsigned int real_index
        cdef float cs, sn
        for parent in work_queue[0]:
            if parent == NULL:
                continue
            real_index = parent.components_index * component_count
            global_pos = <PositionStruct2D*>component_data[real_index + 0]
            global_rot = <RotateStruct2D*>component_data[real_index + 1]
            local_pos = <PositionStruct2D*>component_data[real_index + 2]
            local_rot = <RotateStruct2D*>component_data[real_index + 3]
            parent_pos = <PositionStruct2D*>component_data[real_index + 4]
            parent_rot = <RotateStruct2D*>component_data[real_index + 5]
            cs = cos(parent_rot.r)
            sn = sin(parent_rot.r)
            global_pos.x = parent_pos.x + (
                local_pos.x * cs - local_pos.y * sn)
            global_pos.y = parent_pos.y + (
                local_pos.x * sn + local_pos.y * cs)
            global_rot.r = parent_rot.r + local_rot.r
        return 1

Factory.register('LocalPositionRotateSystem2D', cls=LocalPositionRotateSystem2D)