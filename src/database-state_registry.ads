--  A small, allocation-free registry of per-database state pointers, guarded by
--  a protected object. Used by the subsystems that bind operations to a
--  database through a (thread-local) current key, so concurrent tasks driving
--  different database handles stay isolated. See
--  docs/concurrency-multidb-plan.md.
--
--  Critically -- this is what avoids the deadlock an earlier attempt hit -- the
--  registry does NO allocation or deallocation while holding the lock: the
--  caller allocates and frees State outside the protected action, and this
--  package only stores and looks up pointers in a fixed, packed plain array
--  (no container tampering, no reallocation). Find is a function (concurrent
--  readers); Insert/Remove are procedures (exclusive).
generic
   type State is limited private;
   type State_Access is access all State;
package Database.State_Registry is

   --  The pointer registered for Key, or null.
   function Find (Key : Natural) return State_Access;

   --  Register Value for Key. If another task registered one first, Winner is
   --  that existing pointer (the caller should free its own allocation);
   --  otherwise Winner is Value.
   procedure Insert
     (Key    : Natural;
      Value  : State_Access;
      Winner : out State_Access);

   --  Unregister Key, returning the pointer that was stored (or null) for the
   --  caller to free outside the lock.
   procedure Remove (Key : Natural; Freed : out State_Access);

end Database.State_Registry;
