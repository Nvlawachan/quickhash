unit diskmodule;
{  Based on my disk imager 'YAFFI' (https://github.com/tedsmith/yaffi),
   this unit enables QuickHash to hash disk drives.

   Quick Hash GUI - A Linux, Windows and Apple Mac GUI for quickly selecting one or more files
                     and generating hash values for them.

   Copyright (C) 2011-2018  Ted Smith www.quickhash-gui.org

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 2 of the License, or
    any later version. This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You can read a copy of the GNU General Public License at
    http://www.gnu.org/licenses/>. Also, http://www.gnu.org/copyleft/gpl.html

    Use of the name 'QuickHash GUI' must refer to this utility
    only and must not be re-used in another tool if based upon this code.
    The code is Copyright of Ted Smith 2011 - 2018 (www.quickhash-gui.org)
}
{$mode objfpc}{$H+}

interface

uses
  {$ifdef UNIX}
  process,
   {$IFDEF UseCThreads}
      cthreads,
    {$ENDIF}
  {$endif}

  {$ifdef Windows}
    Process, Windows, ActiveX, ComObj, Variants,
    win32proc, GPTMBR, uGPT, // for the OS name detection : http://free-pascal-lazarus.989080.n3.nabble.com/Lazarus-WindowsVersion-td4032307.html
  {$endif}
    diskspecification, uProgress, Classes, SysUtils, FileUtil,
    Forms, Controls, Graphics, LazUTF8, strutils,
    Dialogs, StdCtrls, ComCtrls, ExtCtrls, Menus, ZVDateTimePicker,

    // DEPRECATED as of v2.8.0
    // sha1Customised, md5Customised,

    // New as of v2.8.0 - HashLib4Pascal Unit, superseeds DCPCrypt.
    HlpHashFactory,
    HlpIHash,
    HlpIHashResult;

type

  { TfrmDiskHashingModule }

  TfrmDiskHashingModule = class(TForm)
    btnRefreshDiskList: TButton;
    btnStartHashing: TButton;
    cbdisks: TComboBox;
    cbLogFile: TCheckBox;
    lblDiskHashSchedulerStatus: TLabel;
    lblschedulertickboxDiskModule: TCheckBox;
    comboHashChoice: TComboBox;
    ledtComputedHashE: TLabeledEdit;
    ledtComputedHashD: TLabeledEdit;
    ledtComputedHashC: TLabeledEdit;
    ledtComputedHashA: TLabeledEdit;
    ledtComputedHashB: TLabeledEdit;
    GroupBox1: TGroupBox;
    ImageList1: TImageList;
    Label1: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    Label4: TLabel;
    Label5: TLabel;
    ledtSelectedItem: TLabeledEdit;
    lt: TLabel;
    ls: TLabel;
    lm: TLabel;
    lv: TLabel;
    menShowDiskManager: TMenuItem;
    menShowDiskTechData: TMenuItem;
    menHashDisk: TMenuItem;
    PopupMenu1: TPopupMenu;
    sdLogFile: TSaveDialog;
    DiskHashingTimer: TTimer;
    TreeView1: TTreeView;
    ZVDateTimePickerDiskModule: TZVDateTimePicker;

    // http://forum.lazarus.freepascal.org/index.php/topic,28560.0.html
    procedure btnAbortHashingClick(Sender: TObject);
    procedure btnRefreshDiskListClick(Sender: TObject);
    procedure btnStartHashingClick(Sender: TObject);
    procedure cbLogFileChange(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormCreate(Sender: TObject);
    procedure lblschedulertickboxDiskModuleChange(Sender: TObject);
    procedure ledtSelectedItemChange(Sender: TObject);
    procedure menHashDiskClick(Sender: TObject);
    procedure menShowDiskManagerClick(Sender: TObject);
    procedure TreeView1SelectionChanged(Sender: TObject);
    function InitialiseHashChoice(Sender : TObject) : Integer;
    procedure cbdisksChange(Sender: TObject);
    function GetDiskTechnicalSpecs(Sender: TObject) : Integer;
    function GetDiskTechnicalSpecsLinux(Sender: TObject) : Integer;
    procedure InvokeDiskHashScheduler (Sender : TObject);
    procedure CheckSchedule(DesiredStartTime : TDateTime);

  private
    { private declarations }
  public
    BytesPerSector : integer;
    StartHashing : boolean;
    NullStrictConvert : boolean;
    { public declarations }
  end;

var
  frmDiskHashingModule: TfrmDiskHashingModule;
  PhyDiskNode, PartitionNoNode, DriveLetterNode           : TTreeNode;
  HashChoice, ExecutionCount : integer;
  slOffsetsOfHits          : TStringList;
  Stop : boolean;

  {$ifdef Windows}
  // These four functions are needed for traversing the attached disks in Windows.
  // Yes, all these for just that!! The joy of Windows coding
  // Credit to RRUZ at SO : https://stackoverflow.com/questions/12271269/how-can-i-correlate-logical-drives-and-physical-disks-using-the-wmi-and-delphi/12271778#comment49108167_12271778
  // https://theroadtodelphi.wordpress.com/2010/12/01/accesing-the-wmi-from-pascal-code-delphi-oxygene-freepascal/#Lazarus
  function ListDrives : string;
  function VarStrNull(const V:OleVariant):string;
  function GetWMIObject(const objectName: String): IDispatch;
  function VarArrayToStr(const vArray: variant): string;
  function RemoveLogicalVolPrefix(strPath : string; LongPathOverrideVal : string) : string;

  // Formatting functions
  function GetDiskLengthInBytes(hSelectedDisk : THandle) : Int64;
  function GetSectorSizeInBytes(hSelectedDisk : THandle) : Int64;
  function GetJustDriveLetter(str : widestring) : string;
  function GetDriveIDFromLetter(str : string) : Byte;
  function GetVolumeName(DriveLetter: Char): string;
  function GetOSName() : string;
  {$endif}

  {$ifdef Unix}
  function ListDrivesLinux : string;
  function GetOSNameLinux() : string;
  function GetBlockCountLinux(s : string) : string;
  function GetBlockSizeLinux(DiskDevName : string) : Integer;
  function GetDiskLabels(DiskDevName : string) : string;
  function GetByteCountLinux(DiskDevName : string) : QWord;

  {$endif}

  function HashDisk(hDiskHandle : THandle; DiskSize : Int64; HashChoice : Integer) : Int64;
  function FormatByteSize(const bytes: QWord): string;
  function ExtractNumbers(s: string): string;

implementation

{$R *.lfm}

{ TfrmDiskHashingModule }


// Enable or disable elements depending on the OS hosting the application
procedure TfrmDiskHashingModule.FormCreate(Sender: TObject);
var
  MissingFileCount : integer;
begin
  Stop := false;
  MissingFileCount := 0;
  ExecutionCount := 0;
  ledtComputedHashA.Enabled := false;
  ledtComputedHashB.Enabled := false;
  ledtComputedHashC.Enabled := false;
  ledtComputedHashD.Enabled := false;
  ledtComputedHashE.Enabled := false;
  {$ifdef CPU64}
  comboHashChoice.Items.Strings[6] := 'xxHash64';
  {$else if CPU32}
  comboHashChoice.Items.Strings[6] := 'xxHash32';
  {$endif}

  {$ifdef Windows}
  // These are the Linux centric elements, so disable them on Windows
  cbdisks.Enabled := false;
  cbdisks.Visible := false;
  Label1.Enabled  := false;
  Label1.Visible  := false;
  Label2.Enabled  := false;
  Label2.Visible  := false;
  Label3.Enabled  := false;
  Label3.Visible  := false;
  Label4.Enabled  := false;
  Label4.Visible  := false;
  Label5.Enabled  := false;
  Label5.Visible  := false;
  lv.Enabled      := false;
  lv.Visible      := false;
  lm.Enabled      := false;
  lm.Visible      := false;
  ls.Enabled      := false;
  ls.Visible      := false;
  lt.Enabled      := false;
  lt.Visible      := false;
 {$endif}
end;

procedure TfrmDiskHashingModule.lblschedulertickboxDiskModuleChange(
  Sender: TObject);
begin
  if lblschedulertickboxDiskModule.Checked then
    begin
     ZVDateTimePickerDiskModule.Enabled := true;
     ZVDateTimePickerDiskModule.Visible := true;
    end
  else
  begin
    ZVDateTimePickerDiskModule.Enabled := false;
    ZVDateTimePickerDiskModule.Visible := false;
  end;
end;

procedure TfrmDiskHashingModule.ledtSelectedItemChange(Sender: TObject);
begin

end;

procedure TfrmDiskHashingModule.btnRefreshDiskListClick(Sender: TObject);
begin
  NullStrictConvert := False; // Hopefully avoid "could not convert variant of type (Null) into type Int64" errors
  {$ifdef Windows}
  try
    TreeView1.Items.Clear;
    ListDrives;
  finally
  end;
  {$endif}
  {$ifdef UNIX}
  try
    Treeview1.Items.Clear;
    ListDrivesLinux;
  finally
  end;
  {$endif}
end;



procedure TfrmDiskHashingModule.btnStartHashingClick(Sender: TObject);
begin
  diskmodule.Stop := false; // if a hash was previously run and aborted, the flag needs to be reset for run 2
  if lblschedulertickboxDiskModule.Checked then
    begin
      InvokeDiskHashScheduler(self);
    end;
  menHashDiskClick(Sender);
end;

// Checks if the desired start date and time has arrived yet by starting timer
// If it has, disable timer. Otherwise, keep it going.
procedure TfrmDiskHashingModule.CheckSchedule(DesiredStartTime : TDateTime);
begin
  if Now = DesiredStartTime then
    begin
      DiskHashingTimer.Enabled := false;
      StartHashing := true;
    end
  else
  begin
    DiskHashingTimer.Enabled := true;
    StartHashing := false;
  end;
end;

procedure TfrmDiskHashingModule.InvokeDiskHashScheduler (Sender : TObject);
var
  scheduleStartTime : TDateTime;
begin
  if ZVDateTimePickerDiskModule.DateTime < Now then
    begin
      ShowMessage('Scheduled start time is in the past. Correct it.');
      exit;
    end
    else begin
      StartHashing := false;
      scheduleStartTime     := ZVDateTimePickerDiskModule.DateTime;
      lblDiskHashSchedulerStatus.Caption := 'Waiting....scheduled for a start time of ' + FormatDateTime('YY/MM/DD HH:MM', schedulestarttime);
      // Set the interval as the milliseconds remaining until the future start time
      DiskHashingTimer.Interval:= trunc((schedulestarttime - Now) * 24 * 60 * 60 * 1000);
      // and then enable the timer
      DiskHashingTimer.Enabled := true;
      // and then check if current date and time is equal to desired scheduled date and time
      repeat
        Application.ProcessMessages;
        CheckSchedule(scheduleStartTime);
      until (StartHashing = true);
    end;
end;

procedure TfrmDiskHashingModule.cbLogFileChange(Sender: TObject);
begin
  if cbLogFile.Checked then cbLogFile.Caption:= 'Create and save a log file';
  if not cbLogFile.Checked then cbLogFile.Caption:= 'No log file required.';
end;

procedure TfrmDiskHashingModule.btnAbortHashingClick(Sender: TObject);
begin
  Stop := true;

  if Stop = TRUE then
  begin
    ledtComputedHashA.Text := 'Process aborted.';
    ledtComputedHashB.Text := 'Process aborted.';
    ledtComputedHashC.Text := 'Process aborted.';
    ledtComputedHashD.Text := 'Process aborted.';
    ledtComputedHashE.Text := 'Process aborted.';
    Abort;
  end;
end;


procedure TfrmDiskHashingModule.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin

end;


// Gets variosu disk properties like model, manufacturer etc, for Linux usage
// Returns a concatanated string for display in the Treeview
function GetDiskLabels(DiskDevName : string) : string;
const
  smodel  = 'ID_MODEL=';
  sserial = 'ID_SERIAL_SHORT=';
  stype   = 'ID_TYPE=';
  svendor = 'ID_VENDOR=';
var

  DiskInfoProcess          : TProcess;
  DiskInfoProcessUDISKS    : TProcess;
  diskinfo, diskinfoUDISKS : TStringList;
  i                        : Integer;
  stmp, strModel, strVendor, strType, strSerial : String;

begin

  // Probe all attached disks and populate the interface
  DiskInfoProcess:=TProcess.Create(nil);
  DiskInfoProcess.Options:=[poWaitOnExit, poUsePipes];
  DiskInfoProcess.CommandLine:='/sbin/udevadm info --query=property --name='+DiskDevName;  //get info about selected disk
  DiskInfoProcess.Execute;

  diskinfo:=TStringList.Create;
  diskinfo.LoadFromStream(DiskInfoProcess.Output);


  for i:=0 to diskinfo.Count-1 do
  begin
    if pos(smodel, diskinfo.Strings[i])>0 then
    begin
      stmp:=diskinfo.Strings[i];
      Delete(stmp, 1, Length(smodel));
      if pos('_', stmp)>0 then
      begin
        strModel:=Copy(stmp, 1, pos('_', stmp)-1);
        Delete(stmp, 1, pos('_', stmp));
        strModel :=stmp;
        if Length(strModel) = 0 then strModel := 'No Value';
      end
      else
      strModel:=stmp;
    end
    else if pos(sserial, diskinfo.Strings[i])>0 then
    begin
      strSerial := Copy(diskinfo.Strings[i], Length(sserial)+1, Length(diskinfo.Strings[i])-Length(sserial));
      if Length(strSerial) = 0 then strSerial := 'No Value';
    end
    else if pos(stype, diskinfo.Strings[i])>0 then
    begin
      strType := Copy(diskinfo.Strings[i], Length(stype)+1, Length(diskinfo.Strings[i])-Length(stype));
      if Length(strType) = 0 then strType := 'No Value';
    end
    else if pos(svendor, diskinfo.Strings[i])>0 then
    begin
      strVendor := Copy(diskinfo.Strings[i], Length(svendor)+1, Length(diskinfo.Strings[i])-Length(svendor));
      if Length(strVendor) = 0 then strVendor := 'No Value';
    end;
  end;
  result := '(Model: ' + strModel + ', Serial No: ' + strSerial + ', Type: ' + strType + ', Vendor: ' + strVendor + ')';
end;

// Delete this eventually, once youre sure the Combo box is redundant
procedure TfrmDiskHashingModule.cbdisksChange(Sender: TObject);
const
  smodel  = 'ID_MODEL=';
  sserial = 'ID_SERIAL_SHORT=';
  stype   = 'ID_TYPE=';
  svendor = 'ID_VENDOR=';
var

  DiskInfoProcess          : TProcess;
  DiskInfoProcessUDISKS    : TProcess;
  diskinfo, diskinfoUDISKS : TStringList;
  i                        : Integer;
  stmp                     : String;
begin

  if cbdisks.ItemIndex<0 then
  exit;
  lv.Caption:='';
  lm.Caption:='';
  ls.Caption:='';
  lt.Caption:='';

  // Probe all attached disks and populate the interface
  DiskInfoProcess:=TProcess.Create(nil);
  DiskInfoProcess.Options:=[poWaitOnExit, poUsePipes];
  DiskInfoProcess.CommandLine:='/sbin/udevadm info --query=property --name='+cbdisks.Text;  //get info about selected disk
  DiskInfoProcess.Execute;

  diskinfo:=TStringList.Create;
  diskinfo.LoadFromStream(DiskInfoProcess.Output);


  for i:=0 to diskinfo.Count-1 do
  begin
    if pos(smodel, diskinfo.Strings[i])>0 then
    begin
      stmp:=diskinfo.Strings[i];
      Delete(stmp, 1, Length(smodel));
      if pos('_', stmp)>0 then
      begin
        lv.Caption:=Copy(stmp, 1, pos('_', stmp)-1);
        Delete(stmp, 1, pos('_', stmp));
        lm.Caption:=stmp;
      end
      else
      lm.Caption:=stmp;
    end
    else if pos(sserial, diskinfo.Strings[i])>0 then
    ls.Caption:=Copy(diskinfo.Strings[i], Length(sserial)+1, Length(diskinfo.Strings[i])-Length(sserial))
    else if pos(stype, diskinfo.Strings[i])>0 then
    lt.Caption:=Copy(diskinfo.Strings[i], Length(stype)+1, Length(diskinfo.Strings[i])-Length(stype))
    else if pos(svendor, diskinfo.Strings[i])>0 then
    begin
      lm.Caption:=lv.Caption+' '+lm.Caption;
      lv.Caption:=Copy(diskinfo.Strings[i], Length(svendor)+1, Length(diskinfo.Strings[i])-Length(svendor));
    end;
  end;

  // Get all technical specifications about a user selected disk and save it
  DiskInfoProcessUDISKS := TProcess.Create(nil);
  DiskInfoProcessUDISKS.Options := [poWaitOnExit, poUsePipes];
  DiskInfoProcessUDISKS.CommandLine := 'udisksctl info -b /dev/' + cbdisks.Text;
  DiskInfoProcessUDISKS.Execute;
  diskinfoUDISKS := TStringList.Create;
  diskinfoUDISKS.LoadFromStream(diskinfoProcessUDISKS.Output);
  diskinfoUDISKS.SaveToFile('TechnicalDiskDetails.txt');

  // Free everything
  diskinfo.Free;
  diskinfoUDISKS.Free;
  DiskInfoProcess.Free;
  DiskInfoProcessUDISKS.Free;
end;


{$ifdef UNIX}
function ListDrivesLinux : string;
var
  DisksProcess: TProcess;
  i: Integer;
  intPhysDiskSize, intLogDiskSize : QWord;
  slDisklist: TSTringList;
  PhyDiskNode, PartitionNoNode, DriveLetterNode           : TTreeNode;
  strPhysDiskSize, strLogDiskSize, DiskDevName, DiskLabels, dmCryptDiscovered   : string;
begin
  intPhysDiskSize := 0;
  DisksProcess:=TProcess.Create(nil);
  DisksProcess.Options:=[poWaitOnExit, poUsePipes];
  DisksProcess.CommandLine:='cat /proc/partitions';   //get all disks/partitions list
  DisksProcess.Execute;
  slDisklist:=TStringList.Create;
  slDisklist.LoadFromStream(DisksProcess.Output);
  slDisklist.Delete(0);  //delete columns name line
  slDisklist.Delete(0);  //delete separator line
  //cbdisks.Items.Clear;

  frmDiskHashingModule.Treeview1.Images := frmDiskHashingModule.ImageList1;
  PhyDiskNode     := frmDiskHashingModule.TreeView1.Items.Add(nil,'Physical Disk') ;
  PhyDiskNode.ImageIndex := 0;

  DriveLetterNode := frmDiskHashingModule.TreeView1.Items.Add(nil,'Logical Volume') ;
  DriveLetterNode.ImageIndex := 1;

  // List physical disks, e.g. sda, sdb, hda, hdb etc
  for i:=0 to slDisklist.Count-1 do
  begin
    if Length(Copy(slDisklist.Strings[i], 26, Length(slDisklist.Strings[i])-25))=3 then
      begin
        DiskDevName := '/dev/' + Trim(RightStr(slDisklist.Strings[i], 3));
        DiskLabels := GetDiskLabels(DiskDevName);
        intPhysDiskSize := GetByteCountLinux(DiskDevName);
        strPhysDiskSize := FormatByteSize(intPhysDiskSize);
        frmDiskHashingModule.TreeView1.Items.AddChild(PhyDiskNode, DiskDevName + ' | ' + strPhysDiskSize + ' ('+IntToStr(intPhysDiskSize)+' bytes) ' + DiskLabels);
      end;
  end;

  // List Logical drives (partitions), e.g. sda1, sdb2, hda1, hdb2 etc
  for i:=0 to slDisklist.Count-1 do
  begin
     dmCryptDiscovered := '';
    if Length(Copy(slDisklist.Strings[i], 26, Length(slDisklist.Strings[i])-25))=4 then
      begin
        DiskDevName := '/dev/' + Trim(RightStr(slDisklist.Strings[i], 4));
        DiskLabels := GetDiskLabels(DiskDevName);

        if Pos('/dm', DiskDevName) > 0 then
        begin
          dmCryptDiscovered := '*** mounted dmCrypt drive! ***';
        end;
        intLogDiskSize := GetByteCountLinux(DiskDevName);
        strLogDiskSize := FormatByteSize(intLogDiskSize);
        frmDiskHashingModule.TreeView1.Items.AddChild(DriveLetterNode, DiskDevName + ' | ' + strLogDiskSize + ' ('+IntToStr(intLogDiskSize)+' bytes)' + dmCryptDiscovered +' ' + DiskLabels);
      end;
  end;
  frmDiskHashingModule.Treeview1.AlphaSort;
  slDisklist.Free;
  DisksProcess.Free;
 end;


// Returns a string holding the disk block COUNT (not size) as extracted from the string from
// /proc/partitions. e.g. : 8  0  312571224 sda

function GetBlockCountLinux(s : string) : string;
var
  strBlockCount : string;
  StartPos, EndPos : integer;
begin
  strBlockCount := '';
  StartPos := 0;
  EndPos := 0;

  EndPos := RPos(Chr($20), s);
  StartPos := RPosEx(Chr($20), s, EndPos-1);
  strBlockCount := Copy(s, StartPos, EndPos-StartPos);
  result := strBlockCount;
end;

function GetBlockSizeLinux(DiskDevName : string) : Integer;
var
  DiskProcess: TProcess;
  BlockSize, StartOffset, i : Integer;
  slDevDisk: TSTringList;
  strBlockSize : string;
  RelLine : boolean;

begin
  RelLine := false;
  BlockSize := 0;
  DiskProcess:=TProcess.Create(nil);
  DiskProcess.Options:=[poWaitOnExit, poUsePipes];
  DiskProcess.CommandLine:='udisksctl info -b ' + DiskDevName;   //get all disks/partitions list
  DiskProcess.Execute;
  slDevDisk := TStringList.Create;
  slDevDisk.LoadFromStream(DiskProcess.Output);

  for i := 0 to slDevDisk.Count -1 do
  begin
    if pos('block size:', slDevDisk.Strings[i]) > 0 then
    begin
      strBlockSize := RightStr(slDevDisk.Strings[i], 4);
      if Length(strBlockSize) > 0 then result := StrToInt(strBlockSize);
    end;
  end;
end;

// Extracts the byte value "Size: " from the output of udisksctl info -b /dev/sdX
function GetByteCountLinux(DiskDevName : string) : QWord;
var
  DiskProcess: TProcess;
  StartOffset, i : Integer;
  slDevDisk: TSTringList;
  strByteCount : string;
  ScanDiskData : boolean;
  intByteCount : QWord;

begin
  ScanDiskData := false;
  result := 0;
  intByteCount := 0;
  strByteCount := '';
  DiskProcess:=TProcess.Create(nil);
  DiskProcess.Options:=[poWaitOnExit, poUsePipes];
  DiskProcess.CommandLine:='udisksctl info -b ' + DiskDevName;   //get all disks/partitions list
  DiskProcess.Execute;
  slDevDisk := TStringList.Create;
  slDevDisk.LoadFromStream(DiskProcess.Output);

  for i := 0 to slDevDisk.Count -1 do
  begin
    // Search for 'Size:' in the output, but note there are two values.
    // This function only wants the first value, so abort once it's found
    if (pos('Size:', slDevDisk.Strings[i]) > 0) and (ScanDiskData = false) then
    begin
      ScanDiskData := true;
      strByteCount := ExtractNumbers(slDevDisk.Strings[i]);
      if Length(strByteCount) > 0 then
        begin
          intByteCount := StrToQWord(strByteCount);
          result := intByteCount;
        end;
    end;
  end;
  slDevDisk.free;
end;
{$endif}

// For extracting the disk size value from the output of udisksctl (from udisk2 package) on Linux
function ExtractNumbers(s: string): string;
var
i: Integer ;
begin
  Result := '' ;
  for i := 1 to length(s) do
  begin
    if s[i] in ['0'..'9'] then
      Result := Result + s[i];
  end;
end;

// Returns the exact disk size for BOTH physical disks and logical drives as
// reported by the Windows API and is used during the imaging stage
function GetDiskLengthInBytes(hSelectedDisk : THandle) : Int64;
const
  // These are defined at the MSDN.Microsoft.com website for DeviceIOControl
  // and https://forum.tuts4you.com/topic/22361-deviceiocontrol-ioctl-codes/
  {
  IOCTL_DISK_GET_DRIVE_GEOMETRY      = $0070000
  IOCTL_DISK_GET_PARTITION_INFO      = $0074004
  IOCTL_DISK_SET_PARTITION_INFO      = $007C008
  IOCTL_DISK_GET_DRIVE_LAYOUT        = $007400C
  IOCTL_DISK_SET_DRIVE_LAYOUT        = $007C010
  IOCTL_DISK_VERIFY                  = $0070014
  IOCTL_DISK_FORMAT_TRACKS           = $007C018
  IOCTL_DISK_REASSIGN_BLOCKS         = $007C01C
  IOCTL_DISK_PERFORMANCE             = $0070020
  IOCTL_DISK_IS_WRITABLE             = $0070024
  IOCTL_DISK_LOGGING                 = $0070028
  IOCTL_DISK_FORMAT_TRACKS_EX        = $007C02C
  IOCTL_DISK_HISTOGRAM_STRUCTURE     = $0070030
  IOCTL_DISK_HISTOGRAM_DATA          = $0070034
  IOCTL_DISK_HISTOGRAM_RESET         = $0070038
  IOCTL_DISK_REQUEST_STRUCTURE       = $007003C
  IOCTL_DISK_REQUEST_DATA            = $0070040
  IOCTL_DISK_CONTROLLER_NUMBER       = $0070044
  IOCTL_DISK_GET_PARTITION_INFO_EX   = $0070048
  IOCTL_DISK_SET_PARTITION_INFO_EX   = $007C04C
  IOCTL_DISK_GET_DRIVE_LAYOUT_EX     = $0070050
  IOCTL_DISK_SET_DRIVE_LAYOUT_EX     = $007C054
  IOCTL_DISK_CREATE_DISK             = $007C058
  IOCTL_DISK_GET_LENGTH_INFO         = $007405C  // Our constant...
  SMART_GET_VERSION                  = $0074080
  SMART_SEND_DRIVE_COMMAND           = $007C084
  SMART_RCV_DRIVE_DATA               = $007C088
  IOCTL_DISK_GET_DRIVE_GEOMETRY_EX   = $00700A0
  IOCTL_DISK_UPDATE_DRIVE_SIZE       = $007C0C8
  IOCTL_DISK_GROW_PARTITION          = $007C0D0
  IOCTL_DISK_GET_CACHE_INFORMATION   = $00740D4
  IOCTL_DISK_SET_CACHE_INFORMATION   = $007C0D8
  IOCTL_DISK_GET_WRITE_CACHE_STATE   = $00740DC
  IOCTL_DISK_DELETE_DRIVE_LAYOUT     = $007C100
  IOCTL_DISK_UPDATE_PROPERTIES       = $0070140
  IOCTL_DISK_FORMAT_DRIVE            = $007C3CC
  IOCTL_DISK_SENSE_DEVICE            = $00703E0
  IOCTL_DISK_INTERNAL_SET_VERIFY     = $0070403
  IOCTL_DISK_INTERNAL_CLEAR_VERIFY   = $0070407
  IOCTL_DISK_INTERNAL_SET_NOTIFY     = $0070408
  IOCTL_DISK_CHECK_VERIFY            = $0074800
  IOCTL_DISK_MEDIA_REMOVAL           = $0074804
  IOCTL_DISK_EJECT_MEDIA             = $0074808
  IOCTL_DISK_LOAD_MEDIA              = $007480C
  IOCTL_DISK_RESERVE                 = $0074810
  IOCTL_DISK_RELEASE                 = $0074814
  IOCTL_DISK_FIND_NEW_DEVICES        = $0074818
  IOCTL_DISK_GET_MEDIA_TYPES         = $0070C00
  }

  // For physical disk access
  IOCTL_DISK_GET_LENGTH_INFO  = $0007405C;

    type
  TDiskLength = packed record
    Length : Int64;
  end;

var
  ByteSize: int64;
  BytesReturned: DWORD;
  DLength: TDiskLength;

begin
  ByteSize      := 0;
  BytesReturned := 0;
  {$ifdef Windows}
  // https://msdn.microsoft.com/en-us/library/aa365178%28v=vs.85%29.aspx
  if not DeviceIOControl(hSelectedDisk,
                         IOCTL_DISK_GET_LENGTH_INFO,
                         nil,
                         0,
                         @DLength,
                         SizeOf(TDiskLength),
                         BytesReturned,
                         nil)
     then raise Exception.Create('Unable to initiate IOCTL_DISK_GET_LENGTH_INFO.');

  if DLength.Length > 0 then ByteSize := DLength.Length;
  result := ByteSize;
  {$endif}
  {$ifdef UNIX}
   // TODO : How to get physical disk size in Linux
  {$endif}
end;

// Obtains the name of the host OS for embedding into the E01 image
// http://free-pascal-lazarus.989080.n3.nabble.com/Lazarus-WindowsVersion-td4032307.html
function GetOSNameLinux() : string;
var
  OSVersion : string;
begin
  // TODO : add an lsb_release parser for Linux distro specifics
  OSVersion := 'Linux ';
  result := OSVersion;
end;


// Returns a human readable view of the number of bytes as Mb, Gb Tb, etc
function FormatByteSize(const bytes: QWord): string;
var
  B: byte;
  KB: word;
  MB: QWord;
  GB: QWord;
  TB: QWord;
begin

  B  := 1; //byte
  KB := 1024 * B; //kilobyte
  MB := 1024 * KB; //megabyte
  GB := 1024 * MB; //gigabyte
  TB := 1024 * GB; //terabyte

  if bytes > TB then
    result := FormatFloat('#.## TiB', bytes / TB)
  else
    if bytes > GB then
      result := FormatFloat('#.## GiB', bytes / GB)
    else
      if bytes > MB then
        result := FormatFloat('#.## MiB', bytes / MB)
      else
        if bytes > KB then
          result := FormatFloat('#.## KiB', bytes / KB)
        else
          result := FormatFloat('#.## bytes', bytes) ;
end;


procedure TfrmDiskHashingModule.TreeView1SelectionChanged(Sender: TObject);
var
  strDriveLetter, strPhysicalDiskID : string;
begin
   if (Sender is TTreeView) and Assigned(TTreeview(Sender).Selected) then
   begin
    if  (TTreeView(Sender).Selected.Text = 'Physical Disk')
      or (TTreeView(Sender).Selected.Text = 'Logical Volume') then
        ledtSelectedItem.Text := '...'
    else
    // If the user Chooses "Drive E:", adjust the selection to "E:" for the Thandle initiation
    // We just copy the characters following "Drive ".
    if Pos('Drive', TTreeView(Sender).Selected.Text) > 0 then
      begin
       strDriveLetter := '\\?\'+Trim(Copy(TTreeView(Sender).Selected.Text, 6, 3));
       ledtSelectedItem.Text := strDriveLetter;
      end
    // If the user chooses a physical disk, adjust the friendly displayed version
    // to an actual low level name the OS can initiate a handle to
    else if Pos('\\.\PHYSICALDRIVE', TTreeView(Sender).Selected.Text) > 0 then
      begin
       // "\\.\PHYSICALDRIVE" = 17 chars, and up to '25' disks allocated so a further
       // 2 chars for that, so 19 chars ibn total.
       strPhysicalDiskID := Trim(Copy(TTreeView(Sender).Selected.Text, 0, 19));
       ledtSelectedItem.Text := strPhysicalDiskID;
      end
    // This is a simple Linux only 'else if' that will catch physical and logical
    else if (Pos('/dev/sd', TTreeView(Sender).Selected.Text) > 0) or  (Pos('/dev/hd', TTreeView(Sender).Selected.Text) > 0) then
      begin
       // "/dev/sd" = 7 chars, and up to '25' disks allocated so a further
       // 2 chars for that, s 9 chars in total.
       strPhysicalDiskID := Trim(Copy(TTreeView(Sender).Selected.Text, 0, 9));
       ledtSelectedItem.Text := strPhysicalDiskID;
      end;
   end;
  end;


// Assigns numeric value to hash algorithm choice to make if else statements used later, faster
function TfrmDiskHashingModule.InitialiseHashChoice(Sender : TObject) : Integer;
begin
  result := -1;

  if comboHashChoice.Text = 'MD5' then
    begin
      result := 1;
    end
      else if comboHashChoice.Text = 'SHA-1' then
        begin
          result := 2;
        end
          else if comboHashChoice.Text = 'MD5 & SHA-1' then
            begin
              result := 3;
            end
              else if comboHashChoice.Text = 'SHA256' then
                begin
                  result := 4;
                end
                  else if comboHashChoice.Text = 'SHA512' then
                    begin
                      result := 5;
                    end
                      else if comboHashChoice.Text = 'SHA-1 & SHA256' then
                        begin
                          result := 6;
                        end
                          else if (comboHashChoice.Text = 'xxHash32') or (comboHashChoice.Text = 'xxHash64') then
                          begin
                            result := 7;
                          end
                            else result := 8;
end;

// Get the technical disk data for a specifically selected disk. Returns 1 on success
// -1 otherwise
function TfrmDiskHashingModule.GetDiskTechnicalSpecs(Sender : TObject) : integer;
{
https://msdn.microsoft.com/en-us/library/aa394132%28v=vs.85%29.aspx
uint32   BytesPerSector;
uint64   DefaultBlockSize;
string   Description;
datetime InstallDate;
string   InterfaceType;
uint32   LastErrorCode;
string   Model;
uint32   Partitions;
uint32   SectorsPerTrack;
string   SerialNumber;
uint32   Signature;
uint64   Size;
string   Status;
uint64   TotalCylinders;
uint32   TotalHeads;
uint64   TotalSectors;
uint64   TotalTracks;
uint32   TracksPerCylinder;
}
{$ifdef Windows}
var

  FSWbemLocator  : Variant;
  objWMIService  : Variant;
  colDiskDrivesWin32DiskDrive  : Variant;
  oEnumDiskDrive : IEnumvariant;
  // http://forum.lazarus.freepascal.org/index.php?topic=24490.0
  objdiskDrive   : OLEVariant;        // Changed from variant to OLE Variant for FPC 3.0.
  nrValue       : LongWord;                  // Added to replace nil pointer for FPC 3.0
  nr            : LongWord absolute nrValue; // FPC 3.0 requires IEnumvariant.next to supply a longword variable for # returned values

  ReportedSectors, DefaultBlockSize, Size, TotalCylinders, TotalTracks : Int64;

  Partitions, SectorsPerTrack,
    WinDiskSignature, TotalHeads, TracksPerCylinder : integer;

  Description, InterfaceType, Model, SerialNumber,
    Status, DiskName, WinDiskSignatureHex, MBRorGPT, GPTData: ansistring;

  SelectedDisk : widestring;

  slDiskSpecs : TStringList;
{$endif}
begin
 {$ifdef Unix}
 GetDiskTechnicalSpecsLinux(Sender);
 {$endif}

 {$ifdef Windows}
  result           := -1;
  DiskName         := '';
  Size             := 0;
  TotalHeads       := 0;
  TotalCylinders   := 0;
  BytesPerSector   := 0;
  WinDiskSignature := 0;
  TotalHeads       := 0;
  TotalTracks      := 0;
  TotalCylinders   := 0;
  TracksPerCylinder:= 0;
  DefaultBlockSize := 0;
  Status           := '';
  Model            := '';
  Description      := '';
  InterfaceType    := '';
  SerialNumber     := '';
  SelectedDisk     := '';
  Partitions       := 0;
  GPTData          := '';
  frmTechSpecs.Memo1.Clear;

  if Pos('\\.\PHYSICALDRIVE', TreeView1.Selected.Text) > 0 then
    begin
      // "\\.\PHYSICALDRIVE" = 17 chars, and up to '25' disks allocated so a further
      // 2 chars for that, so 19 chars ibn total.
      SelectedDisk := Trim(Copy(TreeView1.Selected.Text, 0, 19));

      // Determine if it a MBR or GPT partitioned disk. Call GPTMBR  and uGPT units...
      MBRorGPT := MBR_or_GPT(SelectedDisk);
      if Pos('GPT', MBRorGPT) > 0 then
        begin
          GPTData := QueryGPT(SelectedDisk);
        end;

      // Now ensure the disk string is suitable for WMI and and so on
      SelectedDisk := ANSIToUTF8(Trim(StringReplace(SelectedDisk,'\','\\',[rfReplaceAll])));
      // Years from now, when this makes no sense, just remember that WMI wants a widestring!!!!
      // Dont spend hours of your life again trying to work that undocumented aspect out.


      FSWbemLocator   := CreateOleObject('WbemScripting.SWbemLocator');
      objWMIService   := FSWbemLocator.ConnectServer('localhost', 'root\CIMV2', '', '');
      colDiskDrivesWin32DiskDrive   := objWMIService.ExecQuery('SELECT * FROM Win32_DiskDrive WHERE DeviceID="'+SelectedDisk+'"', 'WQL');
      oEnumDiskDrive  := IUnknown(colDiskDrivesWin32DiskDrive._NewEnum) as IEnumVariant;

      // Parse the Win32_Diskdrive WMI.
      while oEnumDiskDrive.Next(1, objdiskDrive, nr) = 0 do
      begin
        // Using VarIsNull ensures null values are just not parsed rather than errors being generated.
        if not VarIsNull(objdiskDrive.TotalSectors)      then ReportedSectors := objdiskDrive.TotalSectors;
        if not VarIsNull(objdiskDrive.BytesPerSector)    then BytesPerSector  := objdiskDrive.BytesPerSector;
        if not VarIsNull(objdiskDrive.Description)       then Description     := objdiskDrive.Description;
        if not VarIsNull(objdiskDrive.InterfaceType)     then InterfaceType   := objdiskDrive.InterfaceType;
        if not VarIsNull(objdiskDrive.Model)             then Model           := objdiskDrive.Model;
        if not VarIsNull(objdiskDrive.Name)              then DiskName        := objdiskDrive.Name;
        if not VarIsNull(objdiskDrive.Partitions)        then Partitions      := objdiskDrive.Partitions;
        if not VarIsNull(objdiskDrive.SectorsPerTrack)   then SectorsPerTrack := objdiskDrive.SectorsPerTrack;
        if not VarIsNull(objdiskDrive.Signature)         then WinDiskSignature:= objdiskDrive.Signature; // also returned by MBR_or_GPT function
        if not VarIsNull(objdiskDrive.Size)              then Size            := objdiskDrive.Size;
        if not VarIsNull(objdiskDrive.Status)            then Status          := objdiskDrive.Status;
        if not VarIsNull(objdiskDrive.TotalCylinders)    then TotalCylinders  := objdiskDrive.TotalCylinders;
        if not VarIsNull(objdiskDrive.TotalHeads)        then TotalHeads      := objdiskDrive.TotalHeads;
        if not VarIsNull(objdiskDrive.TotalTracks)       then TotalTracks     := objdiskDrive.TotalTracks;
        if not VarIsNull(objdiskDrive.TracksPerCylinder) then TracksPerCylinder:= objdiskDrive.TracksPerCylinder;
        if not VarIsNull(objdiskDrive.DefaultBlockSize)  then DefaultBlockSize:= objdiskDrive.DefaultBlockSize;
        //if not VarIsNull(objdiskDrive.Manufacturer)      then Manufacturer    := objdiskDrive.Manufacturer; WMI just reports "Standard Disk Drives"
        if not VarIsNull(objdiskDrive.SerialNumber)      then SerialNumber    := objdiskDrive.SerialNumber;

        WinDiskSignatureHex := IntToHex(SwapEndian(WinDiskSignature), 8);

        if Size > 0 then
        begin
          slDiskSpecs := TStringList.Create;
          slDiskSpecs.Add('Disk ID: '          + DiskName);
          slDiskSpecs.Add('Bytes per Sector: ' + IntToStr(BytesPerSector));
          slDiskSpecs.Add('Description: '      + Description);
          slDiskSpecs.Add('Interface type: '   + InterfaceType);
          slDiskSpecs.Add('Model: '            + Model);
          //slDiskSpecs.Add('Manufacturer: '     + Manufacturer);
          slDiskSpecs.Add('MBR or GPT? '       + MBRorGPT);
          slDiskSpecs.Add('No of Partitions: ' + IntToStr(Partitions));
          slDiskSpecs.Add('Serial Number: '    + SerialNumber);
          slDiskSpecs.Add('Windows Disk Signature (from offset 440d): ' + WinDiskSignatureHex);
          slDiskSpecs.Add('Size: '             + IntToStr(Size) + ' bytes (' + FormatByteSize(Size) + ').');
          slDiskSpecs.Add('Status: '           + Status);
          slDiskSpecs.Add('Cylinders: '        + IntToStr(TotalCylinders));
          slDiskSpecs.Add('Heads: '            + IntToStr(TotalHeads));
          slDiskSpecs.Add('Reported Sectors: '  + IntToStr(ReportedSectors));
          slDiskSpecs.Add('Tracks: '            + IntToStr(TotalTracks));
          slDiskSpecs.Add('Sectors per Track: ' + IntToStr(SectorsPerTrack));
          slDiskSpecs.Add('Tracks per Cylinder: ' + IntToStr(TracksPerCylinder));
          slDiskSpecs.Add('Default Block Size: ' + IntToStr(DefaultBlockSize));
          slDiskSpecs.Add('= = = = = = = = = = = = = = = = = = =');
          // Only add GPT related data if GPT partitioning was detected earlier
          if Pos('GPT', MBRorGPT) > 0 then
          begin
            slDiskSpecs.Add('GPT Partition Data (if found) : ');
            slDiskSpecs.Add('  ');
            slDiskSpecs.Add(GPTData);
          end;

          result := 1;

          frmTechSpecs.Memo1.Lines.AddText(slDiskSpecs.Text);
          frmTechSpecs.Show;
          slDiskSpecs.Free;
        end
        else result := -1;
      end;
      objdiskDrive:=Unassigned;
    end; // end of if PHYSICAL DRIVEX

  // If the user tries to generate such data for a logical volume, tell him he can't yet.
  // TODO : Add detailed offset parameters for partitions and such
  if Pos('Drive', TreeView1.Selected.Text) > 0 then
    begin
      ShowMessage('Logical volume details are not available yet. Maybe in the future. ');
    end;
  {$endif}
end;

function TfrmDiskHashingModule.GetDiskTechnicalSpecsLinux(Sender : TObject) : integer;
var
  DiskInfoProcessUDISKS    : TProcess;
  diskinfoUDISKS : TStringList;
begin
  // Get all technical specifications about a user selected disk and save it
  DiskInfoProcessUDISKS := TProcess.Create(nil);
  DiskInfoProcessUDISKS.Options := [poWaitOnExit, poUsePipes];
  DiskInfoProcessUDISKS.CommandLine := 'udisksctl info -b ' + Treeview1.Selected.Text;
  DiskInfoProcessUDISKS.Execute;

  diskinfoUDISKS := TStringList.Create;
  diskinfoUDISKS.LoadFromStream(diskinfoProcessUDISKS.Output);

  frmTechSpecs.Memo1.Lines.AddText(diskinfoUDISKS.Text);
  frmTechSpecs.Show;

  // Free everything
  diskinfoUDISKS.Free;
  DiskInfoProcessUDISKS.Free;
end;

// menHashDiskClick - OnClick event for right clicking a disk in the treeview and choosing "Hash this disk"
// Makes a call to HashDisk after collecting all data about the disk first
procedure TfrmDiskHashingModule.menHashDiskClick(Sender: TObject);
const
  // These values are needed for For FSCTL_ALLOW_EXTENDED_DASD_IO to work properly
  // on logical volumes. They are sourced from
  // https://github.com/magicmonty/delphi-code-coverage/blob/master/3rdParty/JCL/jcl-2.3.1.4197/source/windows/JclWin32.pas
  FILE_DEVICE_FILE_SYSTEM = $00000009;
  FILE_ANY_ACCESS = 0;
  METHOD_NEITHER = 3;
  FSCTL_ALLOW_EXTENDED_DASD_IO = ((FILE_DEVICE_FILE_SYSTEM shl 16)
                                   or (FILE_ANY_ACCESS shl 14)
                                   or (32 shl 2) or METHOD_NEITHER);

  var
    SourceDevice                            : widestring;
    hSelectedDisk                           : THandle;
    ExactDiskSize, SectorCount, HashResult  : Int64;
    ExactSectorSize                         : integer;
    slHashLog                               : TStringList;
    BytesReturned                           : DWORD;
    StartedAt, EndedAt, TimeTakenToHash     : TDateTime;

  begin
    BytesReturned   := 0;
    ExactDiskSize   := 0;
    ExactSectorSize := 0;
    SectorCount     := 0;
    HashResult      := 0;
    HashChoice      := -1;
    StartedAt       := 0;
    EndedAt         := 0;
    TimeTakenToHash := 0;
    SourceDevice    := ledtSelectedItem.Text;
    comboHashChoice.Enabled  := false;

    // Determine what hash algorithm to use.
    // MD5 = 1, SHA-1 = 2, MD5 & SHA-1 = 3, SHA256 = 4,
    // SHA512 = 5, SHA-1 & SHA256 = 6, Use Non = 7. -1 is false
    HashChoice := frmDiskHashingModule.InitialiseHashChoice(nil);
    if HashChoice = -1 then abort;

    // Create handle to source disk in the most graceful of ways.
    // -1 returned if fails
    hSelectedDisk := FileOpen(SourceDevice, fmOpenRead OR fmShareDenyNone);

    // Check if handle is valid before doing anything else
    if hSelectedDisk = -1 then
    begin
     ShowMessage('Could not get exclusive disk access ' +
     'OS error and code : ' + SysErrorMessageUTF8(GetLastOSError));
    end
    else
      begin
        // If chosen device is logical volume, initiate FSCTL_ALLOW_EXTENDED_DASD_IO
        // to ensure all sectors acquired, even those protected by the OS normally.
        // https://msdn.microsoft.com/en-us/library/windows/desktop/aa363147%28v=vs.85%29.aspx
        // https://msdn.microsoft.com/en-us/library/windows/desktop/aa364556%28v=vs.85%29.aspx
        {$ifdef Windows}
        if Pos('?', SourceDevice) > 0 then
          begin
            if not DeviceIOControl(hSelectedDisk, FSCTL_ALLOW_EXTENDED_DASD_IO, nil, 0,
                 nil, 0, BytesReturned, nil) then
                   raise Exception.Create('Unable to initiate FSCTL_ALLOW_EXTENDED_DASD_IO.');
          end;

        // Source disk handle is OK. So attempt reading it and adjust display to
        // the friendly version, i.e. '\\?\F:' becomes 'F:'
        ledtSelectedItem.Text := RemoveLogicalVolPrefix(ledtSelectedItem.Text, '\\?\');

        // First, compute the exact disk size of the disk or volume

        ExactDiskSize   := GetDiskLengthInBytes(hSelectedDisk);
        {$endif}
        {$ifdef UNIX}
        ExactDiskSize   := GetByteCountLinux(SourceDevice);
        {$endif}

        // Now query the sector size.
        // 512 bytes is common with MBR but with GPT disks, 1024 or 4096 is likely
        {$ifdef Windows}
        ExactSectorSize := GetSectorSizeInBytes(hSelectedDisk);
        {$endif}
        {$ifdef Unix}
        ExactSectorSize := GetBlockSizeLinux(SourceDevice);
        {$endif}

        // Now we can assign a sector count based on sector size and disk size
        SectorCount   := ExactDiskSize DIV ExactSectorSize;

        frmProgress.lblTotalBytesSource.Caption := ' bytes hashed of ' + IntToStr(ExactDiskSize);

        // Now hash the chosen device, passing the exact size and
        // hash selection and Image name.
        StartedAt := Now;
        frmProgress.lblResult.Caption := 'Hashing ' + ledtSelectedItem.Text;
        frmProgress.lblProgressStartTime.Caption := 'Started At: ' + FormatDateTime('YY/MM/DD HH:MM:SS', StartedAt);
        // Start the disk hashing...
        HashResult := HashDisk(hSelectedDisk, ExactDiskSize, HashChoice);
        // Disk hashing completed
        If HashResult = ExactDiskSize then
          begin
          frmProgress.lblStatus.Caption := 'Disk hashed OK. ' + IntToStr(ExactDiskSize)+' bytes read.';
          frmProgress.lblResult.Caption := 'Finished hashing ' + ledtSelectedItem.Text;
          EndedAt := Now;
          TimeTakenToHash := EndedAt - StartedAt;
          frmProgress.lblProgressEndedAt.Caption := 'Ended At: '     + FormatDateTime('YY/MM/DD HH:MM:SS', EndedAt);
          frmProgress.lblProgressTimeTaken.Caption := 'Time Taken: ' + FormatDateTime('HHH:MM:SS', TimeTakenToHash);
          end
        else
          begin
            ShowMessage('Disk hashing failed or was aborted.' + #13#10 +
                         'Only ' + IntToStr(HashResult) + ' bytes read of the reported ' + IntToStr(ExactDiskSize));
            frmDiskHashingModule.ledtComputedHashA.Text := 'Aborted or failed to compute';
            frmDiskHashingModule.ledtComputedHashB.Text := 'Aborted or failed to compute';
            frmDiskHashingModule.ledtComputedHashC.Text := 'Aborted or failed to compute';
            frmDiskHashingModule.ledtComputedHashD.Text := 'Aborted or failed to compute';
            frmDiskHashingModule.ledtComputedHashE.Text := 'Aborted or failed to compute';
          end;

        // Release existing handle to disk
        try
          if (hSelectedDisk > 0) then
            FileClose(hSelectedDisk);
        finally
          comboHashChoice.Enabled  := true;
        end;

         // Log the actions
        try
          slHashLog := TStringList.Create;
          slHashLog.Add('Disk hashed using: '          + frmDiskHashingModule.Caption);
          {$ifdef WIndows}
          slHashLog.Add('Using operating system: '    + GetOSName);
          {$endif}
          {$ifdef Unix}
          slHashLog.Add('Using operating system: '    + GetOSNameLinux);
          {$endif}
          slHashLog.Add('Device ID: '                 + SourceDevice);
          slHashLog.Add('Chosen Hash Algorithm: '     + comboHashChoice.Text);
          slHashLog.Add('=======================');
          slHashLog.Add('Hashing Started At: '        + FormatDateTime('YY/MM/DD HH:MM:SS', StartedAt));
          slHashLog.Add('Hashing Ended At:   '        + FormatDateTime('YY/MM/DD HH:MM:SS', EndedAt));
          slHashLog.Add('Time Taken to hash: '        + FormatDateTime('HHH:MM:SS', TimeTakenToHash));
          slHashLog.Add('Hash(es) of disk : '                + #13#10 +
                        ' MD5:    ' + ledtComputedHashA.Text + #13#10 +
                        ' SHA-1:  ' + ledtComputedHashB.Text + #13#10 +
                        ' SHA256: ' + ledtComputedHashC.Text + #13#10 +
                        ' SHA512: ' + ledtComputedHashD.Text + #13#10 +
                        ' xxHash: ' + ledtComputedHashE.Text + #13#10);
          slHashLog.Add('=======================');
        finally
        // Save the logfile
        if cbLogFile.Checked then
          begin
           sdLogFile.DefaultExt := 'txt';
           sdLogFile.Filter := 'Text file|*.txt';
           sdLogFile.InitialDir := GetCurrentDir;
           sdLogFile.Title := 'Save your log file as...';
           if sdLogFile.Execute then
             begin
               try
                 frmProgress.Close;
                 slHashLog.SaveToFile(sdLogFile.FileName);
               finally
                 slHashLog.free;
               end;
             end else slHashLog.free; // free it anyway if user doesnt want log file
           end;
        end; // End of finally
      end; // end of the 'else' statement relating to the disk handle being initiated OK
    Application.ProcessMessages;
  end;


// RemoveLogicalVolPrefix : Converts '\\?\F:' to 'F:'
// For display purposes only
function RemoveLogicalVolPrefix(strPath : string; LongPathOverrideVal : string) : string;
begin
  result := '';
  if LongPathOverrideVal = '\\?\' then
  begin
    // Delete the UNC API prefix of '\\?\' from the display
    result := Copy(strPath, 5, (Length(strPath) - 3));
  end;
end;

// Hash the selected disk. Returns the number of bytes successfully hashed
function HashDisk(hDiskHandle : THandle; DiskSize : Int64; HashChoice : Integer) : Int64;
var
  // Buffer size has to be divisible by the disk size.
  // 64Kb buffer works well. Other options are 8191 (8Kb) 32767 (32Kb) or
  // 1048576 (1Mb) or 262144 (240Kb) or 131072 (120Kb buffer)
  Buffer                   : array [0..65535] of Byte;
  BytesRead, LoopItterator : integer;
  TotalBytesRead           : Int64;
  // New HashLib4Pascal hash digests for disk reading in v2.8.0 upwards.
  // DCPCrypt digests deprecated.
  HashInstanceMD5, HashInstanceSHA1, HashInstanceSHA256, HashInstanceSHA512: IHash;
  HashInstanceResultMD5, HashInstanceResultSHA1, HashInstanceResultSHA256, HashInstanceResultSHA512 : IHashResult;

  {$ifdef CPU64}
    HashInstancexxHash64       : IHash;
    HashInstancexxHash64Result : IHashResult;
  {$else ifdef CPU32}
    HashInstancexxHash32       : IHash;
    HashInstancexxHash32Result : IHashResult;
  {$endif}


begin
  BytesRead           := 0;
  TotalBytesRead      := 0;
  LoopItterator       := 0;
  frmProgress.ProgressBar1.Position := 0;
  frmProgress.lblTotalBytesSource.Caption := ' bytes read of ' + IntToStr(DiskSize);
  frmProgress.lblStatus.Caption := ' Hashing disk...please wait';

  // Initialise buffer
  FillChar(Buffer, SizeOf(Buffer), 0);

  frmProgress.Show;

  try
    // Initialise the hash digests in accordance with the users chosen algorithm
    if HashChoice = 1 then
      begin
        HashInstanceMD5 := THashFactory.TCrypto.CreateMD5();
        HashInstanceMD5.Initialize();
      end
        else if HashChoice = 2 then
          begin
            HashInstanceSHA1 := THashFactory.TCrypto.CreateSHA1();
            HashInstanceSHA1.Initialize();
          end
            else if HashChoice = 3 then
              begin
               HashInstanceMD5 := THashFactory.TCrypto.CreateMD5();
               HashInstanceMD5.Initialize();
               HashInstanceSHA1 := THashFactory.TCrypto.CreateSHA1();
               HashInstanceSHA1.Initialize();
              end
                else if HashChoice = 4 then
                  begin
                    HashInstanceSHA256 := THashFactory.TCrypto.CreateSHA2_256();
                    HashInstanceSHA256.Initialize();
                  end
                    else if HashChoice = 5 then
                    begin
                      HashInstanceSHA512 := THashFactory.TCrypto.CreateSHA2_512();
                      HashInstanceSHA512.Initialize();
                    end
                      else if HashChoice = 6 then // SHA-1 & SHA256
                      begin
                        HashInstanceSHA1 := THashFactory.TCrypto.CreateSHA1();
                        HashInstanceSHA1.Initialize();
                        HashInstanceSHA256 := THashFactory.TCrypto.CreateSHA2_256();
                        HashInstanceSHA256.Initialize();
                      end
                        else if HashChoice = 7 then // Uber fast xxHash
                        begin
                         {$ifdef CPU64}
                          HashInstancexxHash64 := THashFactory.THash64.CreateXXHash64();
                          HashInstancexxHash64.Initialize();
                         {$else ifdef CPU32}
                          HashInstancexxHash32 := THashFactory.THash32.CreateXXHash32();
                          HashInstancexxHash32.Initialize();
                         {$endif}
                        end
                          else if HashChoice = 8 then
                            begin
                             // No hashing initiliased
                            end;
    // Now to seek to start of device
    FileSeek(hDiskHandle, 0, 0);
      repeat
        // Read device in buffered segments. Hash the disk and image portions as we go
        if (DiskSize - TotalBytesRead) < SizeOf(Buffer) then
          begin
            // If amount left to read is less than buffer size
            BytesRead    := FileRead(hDiskHandle, Buffer, (DiskSize - TotalBytesRead));
            if BytesRead = -1 then
            begin
              ShowMessage('Disk read error near byte ' + IntToStr(TotalBytesRead) + '. ' + SysErrorMessageUTF8(GetLastOSError));
              exit;
            end
              else inc(TotalBytesRead, BytesRead);
          end
          else
            begin
              // But if amount left to read is equal to buffer capacity, just read the full amount
              BytesRead    := FileRead(hDiskHandle, Buffer, SizeOf(Buffer));
              if BytesRead = -1 then
                begin
                  ShowMessage('Disk read error near byte ' + IntToStr(TotalBytesRead) + '. ' + SysErrorMessageUTF8(GetLastOSError));
                  exit;
                end
                  else inc(TotalBytesRead, BytesRead);
            end;
        frmProgress.lblTotalBytesRead.Caption:= IntToStr(TotalBytesRead);
        frmProgress.ProgressBar1.Position := Trunc((TotalBytesRead/DiskSize)*100);
        frmProgress.lblPercent.Caption := ' (' + IntToStr(frmProgress.ProgressBar1.Position) + '%)';

        // Hash the bytes read and\or written using the algorithm required
        // If the user selected no hashing, break the loop immediately; faster
        if HashChoice = 7 then
          begin
           // No hashing initiliased
          end
          else if HashChoice = 1 then
            begin
              HashInstanceMD5.TransformUntyped(Buffer, BytesRead);
            end
              else if HashChoice = 2 then
                begin
                 HashInstanceSHA1.TransformUntyped(Buffer, BytesRead);
                end
                  else if HashChoice = 3 then
                    begin
                      HashInstanceMD5.TransformUntyped(Buffer, BytesRead);
                      HashInstanceSHA1.TransformUntyped(Buffer, BytesRead);
                    end
                      else if HashChoice = 4 then
                        begin
                         HashInstanceSHA256.TransformUntyped(Buffer, BytesRead);
                        end
                          else if HashChoice = 5 then
                            begin
                             HashInstanceSHA512.TransformUntyped(Buffer, BytesRead);
                            end
                              else if HashChoice = 6 then
                                begin
                                 HashInstanceSHA1.TransformUntyped(Buffer, BytesRead);
                                 HashInstanceSHA256.TransformUntyped(Buffer, BytesRead);
                                end
                                  else if HashChoice = 7 then
                                  begin
                                    {$ifdef CPU64}
                                     HashInstancexxHash64.TransformUntyped(Buffer, BytesRead);
                                    {$else if CPU32}
                                     HashInstancexxHash32.TransformUntyped(Buffer, BytesRead);
                                    {$endif}
                                  end;
      // Only refresh the interface when a few loops have gone by
      inc(LoopItterator, 1);
      if LoopItterator = 150 then
        begin
          LoopItterator := 0;
          Application.ProcessMessages;
        end;
      until (TotalBytesRead = DiskSize) or (Stop = true);
  finally
    // Compute the final hashes of disk and image
    if HashChoice = 1 then
      begin
       HashInstanceResultMD5 := HashInstanceMD5.TransformFinal();
        begin
          // MD5 Disk hash
          frmDiskHashingModule.ledtComputedHashA.Clear;
          frmDiskHashingModule.ledtComputedHashA.Visible := true;
          frmDiskHashingModule.ledtComputedHashA.Enabled := true;
          frmDiskHashingModule.ledtComputedHashA.Text    := Uppercase(HashInstanceResultMD5.ToString());
          frmDiskHashingModule.ledtComputedHashB.Visible := false;
          frmDiskHashingModule.ledtComputedHashC.Enabled := false;
          frmDiskHashingModule.ledtComputedHashC.Visible := false;
          frmDiskHashingModule.ledtComputedHashD.Enabled := false;
          frmDiskHashingModule.ledtComputedHashD.Visible := false;
          frmDiskHashingModule.ledtComputedHashE.Enabled := false;
          frmDiskHashingModule.ledtComputedHashE.Visible := false;
        end;
      end
        else if HashChoice = 2 then
          begin
            // SHA-1 hash only
            HashInstanceResultSHA1 := HashInstanceSHA1.TransformFinal();
            begin
              // SHA1 Disk Hash
              frmDiskHashingModule.ledtComputedHashA.Visible := false;
              frmDiskHashingModule.ledtComputedHashA.Clear;
              frmDiskHashingModule.ledtComputedHashB.Clear;
              frmDiskHashingModule.ledtComputedHashB.Enabled := true;
              frmDiskHashingModule.ledtComputedHashB.Visible := true;
              frmDiskHashingModule.ledtComputedHashB.Text    := Uppercase(HashInstanceResultSHA1.ToString());
              frmDiskHashingModule.ledtComputedHashC.Enabled := false;
              frmDiskHashingModule.ledtComputedHashC.Visible := false;
              frmDiskHashingModule.ledtComputedHashD.Enabled := false;
              frmDiskHashingModule.ledtComputedHashD.Visible := false;
              frmDiskHashingModule.ledtComputedHashE.Enabled := false;
              frmDiskHashingModule.ledtComputedHashE.Visible := false;
            end;
          end
            else if HashChoice = 3 then
              begin
                // MD5 and SHA-1 together
                HashInstanceResultMD5  := HashInstanceMD5.TransformFinal();
                HashInstanceResultSHA1 := HashInstanceSHA1.TransformFinal();
                // Disk hash
                frmDiskHashingModule.ledtComputedHashA.Clear;
                frmDiskHashingModule.ledtComputedHashA.Visible := true;
                frmDiskHashingModule.ledtComputedHashA.Enabled := true;
                frmDiskHashingModule.ledtComputedHashA.Text    := Uppercase(HashInstanceResultMD5.ToString());

                frmDiskHashingModule.ledtComputedHashB.Clear;
                frmDiskHashingModule.ledtComputedHashB.Visible := true;
                frmDiskHashingModule.ledtComputedHashB.Enabled := true;
                frmDiskHashingModule.ledtComputedHashB.Text    := Uppercase(HashInstanceResultSHA1.ToString());
                frmDiskHashingModule.ledtComputedHashC.Enabled := false;
                frmDiskHashingModule.ledtComputedHashC.Visible := false;
                frmDiskHashingModule.ledtComputedHashD.Enabled := false;
                frmDiskHashingModule.ledtComputedHashD.Visible := false;
                frmDiskHashingModule.ledtComputedHashE.Enabled := false;
                frmDiskHashingModule.ledtComputedHashE.Visible := false;
              end
            else if HashChoice = 4 then
              begin
                // SHA-256 hash only
                HashInstanceResultSHA256 := HashInstanceSHA256.TransformFinal();
                begin
                  // SHA256 Disk Hash
                  frmDiskHashingModule.ledtComputedHashA.Enabled := false;
                  frmDiskHashingModule.ledtComputedHashA.Visible := false;
                  frmDiskHashingModule.ledtComputedHashA.Clear;
                  frmDiskHashingModule.ledtComputedHashB.Clear;
                  frmDiskHashingModule.ledtComputedHashB.Enabled := false;
                  frmDiskHashingModule.ledtComputedHashB.Visible := false;
                  frmDiskHashingModule.ledtComputedHashC.Clear;
                  frmDiskHashingModule.ledtComputedHashC.Enabled := true;
                  frmDiskHashingModule.ledtComputedHashC.Visible := true;
                  frmDiskHashingModule.ledtComputedHashC.Text    := Uppercase(HashInstanceResultSHA256.ToString());
                  frmDiskHashingModule.ledtComputedHashD.Clear;
                  frmDiskHashingModule.ledtComputedHashD.Enabled := false;
                  frmDiskHashingModule.ledtComputedHashD.Visible := false;
                  frmDiskHashingModule.ledtComputedHashE.Clear;
                  frmDiskHashingModule.ledtComputedHashE.Enabled := false;
                  frmDiskHashingModule.ledtComputedHashE.Visible := false;
                end;
              end
            else if HashChoice = 5 then
              begin
                // SHA-512 hash only
                HashInstanceResultSHA512 := HashInstanceSHA512.TransformFinal();
                begin
                  // SHA512 Disk Hash
                  frmDiskHashingModule.ledtComputedHashA.Enabled := false;
                  frmDiskHashingModule.ledtComputedHashA.Visible := false;
                  frmDiskHashingModule.ledtComputedHashA.Clear;
                  frmDiskHashingModule.ledtComputedHashB.Clear;
                  frmDiskHashingModule.ledtComputedHashB.Enabled := false;
                  frmDiskHashingModule.ledtComputedHashB.Visible := false;
                  frmDiskHashingModule.ledtComputedHashC.Clear;
                  frmDiskHashingModule.ledtComputedHashC.Enabled := false;
                  frmDiskHashingModule.ledtComputedHashC.Visible := false;
                  frmDiskHashingModule.ledtComputedHashD.Clear;
                  frmDiskHashingModule.ledtComputedHashD.Enabled := true;
                  frmDiskHashingModule.ledtComputedHashD.Visible := true;
                  frmDiskHashingModule.ledtComputedHashD.Text    := Uppercase(HashInstanceResultSHA512.ToString());
                  frmDiskHashingModule.ledtComputedHashE.Clear;
                  frmDiskHashingModule.ledtComputedHashE.Enabled := false;
                  frmDiskHashingModule.ledtComputedHashE.Visible := false;
                end;
              end
            else if HashChoice = 6 then
              begin
                // SHA-1 & SHA-256 hash only
               HashInstanceResultSHA1 := HashInstanceSHA1.TransformFinal();
               HashInstanceResultSHA256 := HashInstanceSHA256.TransformFinal();
                begin
                  // SHA-1 & SHA256 Disk Hash
                  frmDiskHashingModule.ledtComputedHashA.Enabled := false;
                  frmDiskHashingModule.ledtComputedHashA.Visible := false;
                  frmDiskHashingModule.ledtComputedHashA.Clear;
                  frmDiskHashingModule.ledtComputedHashB.Clear;
                  frmDiskHashingModule.ledtComputedHashB.Enabled := true;
                  frmDiskHashingModule.ledtComputedHashB.Visible := true;
                  frmDiskHashingModule.ledtComputedHashB.Text    := Uppercase(HashInstanceResultSHA1.ToString());
                  frmDiskHashingModule.ledtComputedHashC.Clear;
                  frmDiskHashingModule.ledtComputedHashC.Enabled := true;
                  frmDiskHashingModule.ledtComputedHashC.Visible := true;
                  frmDiskHashingModule.ledtComputedHashC.Text    := Uppercase(HashInstanceResultSHA256.ToString());
                  frmDiskHashingModule.ledtComputedHashD.Clear;
                  frmDiskHashingModule.ledtComputedHashD.Enabled := false;
                  frmDiskHashingModule.ledtComputedHashD.Visible := false;
                  frmDiskHashingModule.ledtComputedHashE.Clear;
                  frmDiskHashingModule.ledtComputedHashE.Enabled := false;
                  frmDiskHashingModule.ledtComputedHashE.Visible := false;
                end;
              end
            else if HashChoice = 7 then
              begin
                // xxHash only
                {$ifdef CPU64}
                  HashInstancexxHash64Result :=  HashInstancexxHash64.TransformFinal();
                {$else if CPU32}
                  HashInstancexxHash32Result :=  HashInstancexxHash32.TransformFinal();
                {$endif}
                begin
                  // xxHash Disk Hash
                  frmDiskHashingModule.ledtComputedHashA.Enabled := false;
                  frmDiskHashingModule.ledtComputedHashA.Visible := false;
                  frmDiskHashingModule.ledtComputedHashA.Clear;
                  frmDiskHashingModule.ledtComputedHashB.Clear;
                  frmDiskHashingModule.ledtComputedHashB.Enabled := false;
                  frmDiskHashingModule.ledtComputedHashB.Visible := false;
                  frmDiskHashingModule.ledtComputedHashB.Clear;
                  frmDiskHashingModule.ledtComputedHashC.Clear;
                  frmDiskHashingModule.ledtComputedHashC.Enabled := false;
                  frmDiskHashingModule.ledtComputedHashC.Visible := false;
                  frmDiskHashingModule.ledtComputedHashC.Clear;
                  frmDiskHashingModule.ledtComputedHashD.Clear;
                  frmDiskHashingModule.ledtComputedHashD.Enabled := false;
                  frmDiskHashingModule.ledtComputedHashD.Visible := false;
                  frmDiskHashingModule.ledtComputedHashE.Clear;
                  frmDiskHashingModule.ledtComputedHashE.Enabled := true;
                  frmDiskHashingModule.ledtComputedHashE.Visible := true;
                  {$ifdef CPU64}
                    frmDiskHashingModule.ledtComputedHashE.Text    := Uppercase(HashInstancexxHash64Result.ToString());
                  {$else if CPU32}
                    frmDiskHashingModule.ledtComputedHashE.Text    := Uppercase(HashInstancexxHash32Result.ToString());
                  {$endif}
                end;
              end
            else if HashChoice = 8 then
                begin
                 frmDiskHashingModule.ledtComputedHashA.Text    := Uppercase('No hash computed');
                 frmDiskHashingModule.ledtComputedHashB.Text    := Uppercase('No hash computed');
                 frmDiskHashingModule.ledtComputedHashC.Text    := Uppercase('No hash computed');
                 frmDiskHashingModule.ledtComputedHashD.Text    := Uppercase('No hash computed');
                 frmDiskHashingModule.ledtComputedHashE.Text    := Uppercase('No hash computed');
                 frmDiskHashingModule.ledtComputedHashA.Enabled := true;
                 frmDiskHashingModule.ledtComputedHashA.Visible := true;
                 frmDiskHashingModule.ledtComputedHashB.Enabled := true;
                 frmDiskHashingModule.ledtComputedHashB.Visible := true;
                 frmDiskHashingModule.ledtComputedHashC.Enabled := true;
                 frmDiskHashingModule.ledtComputedHashC.Visible := true;
                 frmDiskHashingModule.ledtComputedHashD.Enabled := true;
                 frmDiskHashingModule.ledtComputedHashD.Visible := true;
                 frmDiskHashingModule.ledtComputedHashE.Enabled := true;
                 frmDiskHashingModule.ledtComputedHashE.Visible := true;
                 frmProgress.lblStatus.Caption      := 'No verification conducted';
                end;
      end;
  result := TotalBytesRead;
end;


procedure TfrmDiskHashingModule.menShowDiskManagerClick(Sender: TObject);
var
ProcDiskManager : TProcess;
begin
  {$ifdef Windows}
  try
    ProcDiskManager            := TProcess.Create(nil);
    ProcDiskManager.Executable := 'mmc.exe';
    ProcDiskManager.Parameters.Add('C:\Windows\System32\diskmgmt.msc');
    ProcDiskManager.Options    := [poWaitOnExit, poUsePipes];
    ProcDiskManager.Execute;
  finally
    ProcDiskManager.Free;
  end;
  {$endif}
  {$ifdef UNIX}
  ShowMessage('Not available on Linux. Use fdisk, or gparted');
  {$endif}
end;

// These are Windows centric functions. Many call upon the Windows API.
{$ifdef Windows}

function VarArrayToStr(const vArray: variant): string;

    function _VarToStr(const V: variant): string;
    var
    Vt: integer;
    begin
    Vt := VarType(V);
        case Vt of
          varSmallint,
          varInteger  : Result := IntToStr(integer(V));
          varSingle,
          varDouble,
          varCurrency : Result := FloatToStr(Double(V));
          varDate     : Result := VarToStr(V);
          varOleStr   : Result := WideString(V);
          varBoolean  : Result := VarToStr(V);
          varVariant  : Result := VarToStr(Variant(V));
          varByte     : Result := char(byte(V));
          varString   : Result := String(V);
          varArray    : Result := VarArrayToStr(Variant(V));
        end;
    end;

var
i : integer;
begin
    Result := '[';
     if (VarType(vArray) and VarArray)=0 then
       Result := _VarToStr(vArray)
    else
    for i := VarArrayLowBound(vArray, 1) to VarArrayHighBound(vArray, 1) do
     if i=VarArrayLowBound(vArray, 1)  then
      Result := Result+_VarToStr(vArray[i])
     else
      Result := Result+'|'+_VarToStr(vArray[i]);

    Result:=Result+']';
end;

function VarStrNull(const V:OleVariant):string; //avoid problems with null strings
begin
  Result:='';
  if not VarIsNull(V) then
  begin
    if VarIsArray(V) then
       Result:=VarArrayToStr(V)
    else
    Result:=VarToStr(V);
  end;
end;

function GetWMIObject(const objectName: String): IDispatch; //create the Wmi instance
var
  chEaten: PULONG;
  BindCtx: IBindCtx;
  Moniker: IMoniker;
begin
  OleCheck(CreateBindCtx(0, bindCtx));
  OleCheck(MkParseDisplayName(BindCtx, StringToOleStr(objectName), chEaten, Moniker));
  OleCheck(Moniker.BindToObject(BindCtx, nil, IDispatch, Result));
end;


function ListDrives : string;
var
  FSWbemLocator  : Variant;
  objWMIService  : Variant;
  colDiskDrivesWin32DiskDrive  : Variant;
  colLogicalDisks: Variant;
  colPartitions  : Variant;

  // http://forum.lazarus.freepascal.org/index.php?topic=24490.0
  objLogicalDisk : OLEVariant;
  objdiskDrive   : OLEVariant;
  objPartition   : OLEVariant;
  // Changed from variant to OLE Variant for FPC 3.0.
  nrValue       : LongWord;                  // Added to replace nil pointer for FPC 3.0
  nr            : LongWord absolute nrValue; // FPC 3.0 requires IEnumvariant.next to supply a longword variable for # returned values
  oEnumDiskDrive : IEnumvariant;
  oEnumPartition : IEnumvariant;
  oEnumLogical   : IEnumvariant;
  Val1, Val2, Val3, Val4,
    DeviceID, s : widestring;
  DriveLetter, strDiskSize, strFreeSpace, strVolumeName    : string;
  DriveLetterID  : Byte;
  intDriveSize, intFreeSpace : Int64;

begin
  Result       := '';
  intDriveSize := 0;
  intFreeSpace := 0;
  frmDiskHashingModule.BytesPerSector := 0;
  frmDiskHashingModule.Treeview1.Images := frmDiskHashingModule.ImageList1;
  PhyDiskNode     := frmDiskHashingModule.TreeView1.Items.Add(nil,'Physical Disk') ;
  PhyDiskNode.ImageIndex := 0;
  {
  PartitionNoNode := frmDiskHashingModule.TreeView1.Items.Add(nil,'Partition No') ;
  PartitionNoNode.ImageIndex := 2;
  }
  DriveLetterNode := frmDiskHashingModule.TreeView1.Items.Add(nil,'Logical Volume') ;
  DriveLetterNode.ImageIndex := 1;

  FSWbemLocator   := CreateOleObject('WbemScripting.SWbemLocator');
  objWMIService   := FSWbemLocator.ConnectServer('localhost', 'root\CIMV2', '', '');
  //colDiskDrivesWin32DiskDrive   := objWMIService.ExecQuery('SELECT DeviceID FROM Win32_DiskDrive', 'WQL');
  colDiskDrivesWin32DiskDrive   := objWMIService.ExecQuery('SELECT * FROM Win32_DiskDrive', 'WQL');

  oEnumDiskDrive  := IUnknown(colDiskDrivesWin32DiskDrive._NewEnum) as IEnumVariant;

  while oEnumDiskDrive.Next(1, objdiskDrive, nr) = 0 do
   begin
      Val1 := Format('%s',[string(objdiskDrive.DeviceID)]) + ' (';
      Val2 := FormatByteSize(objdiskDrive.Size)            + ') ';
      Val3 := Format('%s',[string(objdiskDrive.Model)]);

      //Format('%s',[string(objdiskDrive.DeviceID)]);
      if Length(Val1) > 0 then
      begin
        frmDiskHashingModule.TreeView1.Items.AddChild(PhyDiskNode, Val1 + Val2 + Val3 + Val4);
      end;
      //Escape the `\` chars in the DeviceID value because the '\' is a reserved character in WMI.
      DeviceID        := StringReplace(objdiskDrive.DeviceID,'\','\\',[rfReplaceAll]);
      //link the Win32_DiskDrive class with the Win32_DiskDriveToDiskPartition class
      s:=Format('ASSOCIATORS OF {Win32_DiskDrive.DeviceID="%s"} WHERE AssocClass = Win32_DiskDriveToDiskPartition',[DeviceID]);
      colPartitions   := objWMIService.ExecQuery(s, 'WQL');
      oEnumPartition  := IUnknown(colPartitions._NewEnum) as IEnumVariant;

      while oEnumPartition.Next(1, objPartition, nr) = 0 do
      begin
       if not VarIsNull(objPartition.DeviceID) then
       begin
        val2 := Format('%s',[string(objPartition.DeviceID)]);
         if Length(Val2) > 0 then
         begin
          // Removed for now, until partition numbers themselves are needed
          // frmDiskHashingModule.TreeView1.Items.AddChild(PartitionNoNode, Val2);
         end;
        //link the Win32_DiskPartition class with theWin32_LogicalDiskToPartition class.
        s:='ASSOCIATORS OF {Win32_DiskPartition.DeviceID="'+VarToStr(objPartition.DeviceID)+'"} WHERE AssocClass = Win32_LogicalDiskToPartition';
        colLogicalDisks := objWMIService.ExecQuery(s);
        oEnumLogical  := IUnknown(colLogicalDisks._NewEnum) as IEnumVariant;

        while oEnumLogical.Next(1, objLogicalDisk, nr) = 0 do
          begin
            Val3 := Format('Drive %s',[string(objLogicalDisk.DeviceID)]);
             if Length(Val3) > 0 then
              begin
                DriveLetter    := GetJustDriveLetter(Val3);
                DriveLetterID  := GetDriveIDFromLetter(DriveLetter);

                intDriveSize   := DiskSize(DriveLetterID);
                if intDriveSize > 0 then
                 begin
                   strDiskSize := FormatByteSize(intDriveSize);
                 end else strDiskSize := '0';

                intFreeSpace   := DiskFree(DriveLetterID);
                if intFreeSpace > 0 then
                begin
                   strFreeSpace   := FormatByteSize(intFreeSpace);
                end else strFreeSpace := '0';

                strVolumeName  := GetVolumeName(DriveLetter[1]);
                frmDiskHashingModule.TreeView1.Items.AddChild(DriveLetterNode, Val3 + ' (' + strVolumeName + ', Size: ' + strDiskSize + ', Free Space: ' + strFreeSpace + ')');
              end;
            objLogicalDisk:=Unassigned;
          end;
       end;
       objPartition:=Unassigned;
      end;
       objdiskDrive:=Unassigned;
   end;
  frmDiskHashingModule.Treeview1.AlphaSort;
end;



// Returns just the drive letter from the treeview, e.g. 'Drive X:' becomes just 'X'
// which can then be passed to GetDriveIDFromLetter
function GetJustDriveLetter(str : widestring) : string;
begin
  // First make "Drive X:" to "X:"
  Delete(str, 1, 6);
  // Now strip out the ':'
  Delete(str, 2, 1);
  result := str;
end;

// Returns the numerical ID stored by Windows of the queried drive letter
function GetDriveIDFromLetter(str : string) : Byte;
begin
  result := (Ord(str[1]))-64;
end;

// Returns the volume name and serial number in Windows of a given mounted drive.
// Note : NOT the serial number of the hard disk itself! Just the volume name.
function GetVolumeName(DriveLetter: Char): string;
var
  buffer                  : array[0..MAX_PATH] of Char;
  strVolName, strVolSerNo : string;
  VolSerNo, dummy         : DWORD;
  oldmode                 : LongInt;

begin
  oldmode := SetErrorMode(SEM_FAILCRITICALERRORS);
  try
    // After stripping it out for GetDriveIDFromLetter to work,
    // we now have to stick back the ':\' to the drive letter! (Gggrrggh, MS Windows)
    GetVolumeInformation(PChar(DriveLetter + ':\'), buffer, SizeOf(buffer), @VolSerNo,
                         dummy, dummy, nil, 0);
    strVolSerNo := IntToHex(HiWord(VolSerNo), 4) + '-' + IntToHex(LoWord(VolSerNo), 4);
    strVolName  := StrPas(buffer);
    Result      := strVolName + ' ' + strVolSerNo; // StrPas(buffer);
  finally
    SetErrorMode(oldmode);
  end;
end;

// GetSectorSizeInBytes queries the disk secotr size. 512 is most common size
// but with GPT disks, 1024 and 4096 bytes will soon be common.
// We're only interested in BytesPerSector by the way - the rest of it is utter rubbish
// in this day and age. LBA is used now by almost all storage devices, with rare exception.
// But the  IOCTL_DISK_GET_DRIVE_GEOMETRY structure expects 5 variables.
function GetSectorSizeInBytes(hSelectedDisk : THandle) : Int64;
type
TDiskGeometry = packed record
  Cylinders            : Int64;    // This is stored just for compliance with the structure
  MediaType            : Integer;  // This is stored just for compliance with the structure
  TracksPerCylinder    : DWORD;    // This is stored just for compliance with the structure
  SectorsPerTrack      : DWORD;    // This is stored just for compliance with the structure
  BytesPerSector       : DWORD;    // This, however, is useful to us!
end;

const
  IOCTL_DISK_GET_DRIVE_GEOMETRY      = $0070000;
var
  DG : TDiskGeometry;
  SectorSizeInBytes, BytesReturned : Integer;

begin
  if not DeviceIOControl(hSelectedDisk,
                         IOCTL_DISK_GET_DRIVE_GEOMETRY,
                         nil,
                         0,
                         @DG,
                         SizeOf(TDiskGeometry),
                         @BytesReturned,
                         nil)
                         then raise Exception.Create('Unable to initiate IOCTL_DISK_GET_DRIVE_GEOMETRY.');

  if DG.BytesPerSector > 0 then
    begin
      result := DG.BytesPerSector;
    end
  else result := -1;
end;

// Obtains the name of the host OS for embedding into the E01 image
// http://free-pascal-lazarus.989080.n3.nabble.com/Lazarus-WindowsVersion-td4032307.html
function GetOSName() : string;
var
  OSVersion : string;
begin
  if WindowsVersion = wv95 then OSVersion              := 'Windows 95 '
   else if WindowsVersion = wvNT4 then OSVersion       := 'Windows NT v.4 '
   else if WindowsVersion = wv98 then OSVersion        := 'Windows 98 '
   else if WindowsVersion = wvMe then OSVersion        := 'Windows ME '
   else if WindowsVersion = wv2000 then OSVersion      := 'Windows 2000 '
   else if WindowsVersion = wvXP then OSVersion        := 'Windows XP '
   else if WindowsVersion = wvServer2003 then OSVersion:= 'Windows Server 2003 '
   else if WindowsVersion = wvVista then OSVersion     := 'Windows Vista '
   else if WindowsVersion = wv7 then OSVersion         := 'Windows 7 '
   else OSVersion:= 'MS Windows ';
  result := OSVersion;
end;
{$endif}

end.

