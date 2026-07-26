with Ada.Containers;
with Ada.Containers.Hashed_Maps;
with Ada.Containers.Indefinite_Vectors;
with Ada.Containers.Vectors;

package body Database.Memory_Store is

   use type Database.Versioning.Transaction_Id;

   package Row_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Natural, Element_Type => Stored_Row);

   function Key_Hash (Key : Table_Key) return Ada.Containers.Hash_Type is
      use type Ada.Containers.Hash_Type;
   begin
      return Ada.Containers.Hash_Type'Mod (Key.State_Key) * 100_003
        + Ada.Containers.Hash_Type'Mod (Key.Table_Id);
   end Key_Hash;

   package Partition_Maps is new Ada.Containers.Hashed_Maps
     (Key_Type        => Table_Key,
      Element_Type    => Row_Vectors.Vector,
      Hash            => Key_Hash,
      Equivalent_Keys => "=",
      "="             => Row_Vectors."=");

   package Key_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Table_Key);

   --  The partition map is guarded by a protected object so that distinct
   --  database handles (which own distinct partitions) may operate on the store
   --  concurrently. Each public operation below is a single protected action.
   protected Store is
      function Get_Snapshot (Key : Table_Key) return Stored_Row_Array;
      procedure Replace (Key : Table_Key; Index : Natural; Value : Stored_Row);
      procedure Add (Key : Table_Key; Value : Stored_Row);
      procedure Purge (Tx_Id : Database.Versioning.Transaction_Id);
      procedure Drop_State (State_Key : Natural);
   private
      Partitions : Partition_Maps.Map;
   end Store;

   protected body Store is

      function Get_Snapshot (Key : Table_Key) return Stored_Row_Array is
         C : constant Partition_Maps.Cursor := Partitions.Find (Key);
      begin
         if not Partition_Maps.Has_Element (C) then
            return Stored_Row_Array'(1 .. 0 => <>);
         end if;
         --  Element returns a copy of the partition; a protected function may
         --  run concurrently, so it must not take a Constant_Reference (that
         --  mutates the container's tamper counter and would race).
         declare
            V      : constant Row_Vectors.Vector := Partition_Maps.Element (C);
            N      : constant Natural := Natural (V.Length);
            Result : Stored_Row_Array (0 .. N - 1);
         begin
            for I in 0 .. N - 1 loop
               Result (I) := V.Element (I);
            end loop;
            return Result;
         end;
      end Get_Snapshot;

      procedure Replace (Key : Table_Key; Index : Natural; Value : Stored_Row) is
         C : constant Partition_Maps.Cursor := Partitions.Find (Key);

         procedure Do_Replace (K : Table_Key; V : in out Row_Vectors.Vector) is
            pragma Unreferenced (K);
         begin
            if Index < Natural (V.Length) then
               V.Replace_Element (Index, Value);
            end if;
         end Do_Replace;
      begin
         if Partition_Maps.Has_Element (C) then
            Partitions.Update_Element (C, Do_Replace'Access);
         end if;
      end Replace;

      procedure Add (Key : Table_Key; Value : Stored_Row) is
         procedure Do_Append (K : Table_Key; V : in out Row_Vectors.Vector) is
            pragma Unreferenced (K);
         begin
            V.Append (Value);
         end Do_Append;
      begin
         if not Partitions.Contains (Key) then
            Partitions.Insert (Key, Row_Vectors.Empty_Vector);
         end if;
         Partitions.Update_Element (Partitions.Find (Key), Do_Append'Access);
      end Add;

      procedure Purge (Tx_Id : Database.Versioning.Transaction_Id) is

         --  Finalize one partition. Only the metadata is inspected, and only the
         --  aborting transaction's own rows are touched, so the (controlled) row
         --  payload is never copied here -- keeping rollback proportional to the
         --  rows the transaction actually wrote, not to the store's size.
         procedure Finalize_Partition
           (K : Table_Key; V : in out Row_Vectors.Vector) is
            pragma Unreferenced (K);
            I : Natural := 0;
         begin
            while I < Natural (V.Length) loop
               if V.Constant_Reference (I).Metadata.Created_By_Tx = Tx_Id then
                  V.Delete (I);
               else
                  if V.Constant_Reference (I).Metadata.Deleted_By_Tx = Tx_Id then
                     Database.Versioning.Clear_Delete (V.Reference (I).Metadata);
                  end if;
                  I := I + 1;
               end if;
            end loop;
         end Finalize_Partition;

         C : Partition_Maps.Cursor := Partitions.First;
      begin
         while Partition_Maps.Has_Element (C) loop
            Partitions.Update_Element (C, Finalize_Partition'Access);
            Partition_Maps.Next (C);
         end loop;
      end Purge;

      procedure Drop_State (State_Key : Natural) is
         Doomed : Key_Vectors.Vector;
         C      : Partition_Maps.Cursor := Partitions.First;
      begin
         --  Collect then delete: a hashed map may not be mutated while iterating.
         while Partition_Maps.Has_Element (C) loop
            if Partition_Maps.Key (C).State_Key = State_Key then
               Doomed.Append (Partition_Maps.Key (C));
            end if;
            Partition_Maps.Next (C);
         end loop;
         for K of Doomed loop
            Partitions.Delete (K);
         end loop;
      end Drop_State;

   end Store;

   function Snapshot (Key : Table_Key) return Stored_Row_Array is
   begin
      return Store.Get_Snapshot (Key);
   end Snapshot;

   procedure Put (Key : Table_Key; Index : Natural; Value : Stored_Row) is
   begin
      Store.Replace (Key, Index, Value);
   end Put;

   procedure Append (Key : Table_Key; Value : Stored_Row) is
   begin
      Store.Add (Key, Value);
   end Append;

   procedure Rollback (Tx_Id : Database.Versioning.Transaction_Id) is
   begin
      Store.Purge (Tx_Id);
   end Rollback;

   procedure Drop (State_Key : Natural) is
   begin
      Store.Drop_State (State_Key);
   end Drop;

end Database.Memory_Store;
