package body Database.Visibility.Rules
  with SPARK_Mode => On
is
   function Created_Is_Visible
     (Tx_Id            : Database.Versioning.Transaction_Id;
      Snapshot         : Database.Versioning.Commit_Version;
      Created_By_Tx    : Database.Versioning.Transaction_Id;
      Created_Version  : Database.Versioning.Commit_Version;
      Created_Committed: Boolean;
      Created_Lifecycle: Database.MVCC.Transaction_Lifecycle) return Boolean
   is
   begin
      if Created_By_Tx = Tx_Id then
         return True;
      end if;

      if not Created_Committed then
         case Created_Lifecycle is
            when Database.MVCC.Committed =>
               return Created_Version <= Snapshot;
            when Database.MVCC.Rolled_Back | Database.MVCC.Active | Database.MVCC.Unknown =>
               return False;
         end case;
      end if;

      return Created_Version <= Snapshot;
   end Created_Is_Visible;

   function Deleted_For
     (Tx_Id             : Database.Versioning.Transaction_Id;
      Snapshot          : Database.Versioning.Commit_Version;
      Deleted           : Boolean;
      Deleted_By_Tx     : Database.Versioning.Transaction_Id;
      Deleted_Version   : Database.Versioning.Commit_Version;
      Deleted_Lifecycle : Database.MVCC.Transaction_Lifecycle) return Boolean
   is
   begin
      if not Deleted then
         return False;
      end if;

      if Deleted_By_Tx = Tx_Id then
         return True;
      end if;

      if Deleted_By_Tx /= Database.Versioning.No_Transaction then
         case Deleted_Lifecycle is
            when Database.MVCC.Committed =>
               return Deleted_Version /= Database.Versioning.No_Version
                 and then Deleted_Version <= Snapshot;
            when Database.MVCC.Rolled_Back | Database.MVCC.Active | Database.MVCC.Unknown =>
               return False;
         end case;
      end if;

      return Deleted_Version /= Database.Versioning.No_Version
        and then Deleted_Version <= Snapshot;
   end Deleted_For;

   function Version_Is_Visible
     (Created_Visible : Boolean;
      Deleted         : Boolean) return Boolean
   is
   begin
      return Created_Visible and then not Deleted;
   end Version_Is_Visible;

   function Is_Own_Write
     (Tx_Id         : Database.Versioning.Transaction_Id;
      Created_By_Tx : Database.Versioning.Transaction_Id;
      Deleted_By_Tx : Database.Versioning.Transaction_Id) return Boolean
   is
   begin
      return Created_By_Tx = Tx_Id or else Deleted_By_Tx = Tx_Id;
   end Is_Own_Write;
end Database.Visibility.Rules;
