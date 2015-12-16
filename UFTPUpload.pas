unit UFTPUpload;

interface

uses
  System.Threading,System.Classes,IdExplicitTLSClientServerBase,IdFTP,IdFTPCommon,
  System.StrUtils,System.SysUtils,IdComponent,Math,IdGlobal,IdGlobalProtocols;

type
  TProgressInfo = record
    progress: Double;
    FileName,speed: string;
    ACount,MaxCount: Int64;
  end;

  //上传进度的回调函数,Handle为线程句柄
  TFnProgress = procedure(h: THandle;pi: TProgressInfo) of object;

  TFTPUploadThread = class(TThread)
  private
    FFTP: TIdFTP;
    FSour,FDest: string;
    FAppend: Boolean;
    FCB: TFnProgress;
    FPos: Int64;
    FCount,FTime: Int64;
    FProgressInfo: TProgressInfo;
    procedure CreateFTPDir;
    procedure OnWorkBegin(ASender: TObject; AWorkMode: TWorkMode; AWorkCountMax: Int64);
    procedure OnWork(ASender: TObject; AWorkMode: TWorkMode; AWorkCount: Int64);
    procedure OnWorkEnd(ASender: TObject; AWorkMode: TWorkMode);
  protected
    procedure Execute; override;
  public
    constructor Create(AHost,AUser,APassword,ASourFile: string;
      ADestFile: string = ''; Append: Boolean = False; cb: TFnProgress = nil); reintroduce;
    destructor Destroy; override;
  end;

implementation

{ TFTPUploadThread }

constructor TFTPUploadThread.Create(AHost, AUser, APassword, ASourFile,
  ADestFile: string;Append: Boolean;cb: TFnProgress);
begin
  inherited Create(False);
  FreeOnTerminate := True;
  FFTP := TIdFTP.Create(nil);
  try
    FFTP.Host := AHost;
    FFTP.Username := AUser;
    FFTP.Password := APassword;
    if Assigned(cb) then
    begin
      FCB := cb;
      FFTP.OnWorkBegin := OnWorkBegin;
      FFTP.OnWork := OnWork;
      FFTP.OnWorkEnd := OnWorkEnd;
    end;
    //路径全部换成'\'
    FSour := StringReplace(ASourFile,'/','\',[rfReplaceAll]);
    FDest := StringReplace(ADestFile,'/','\',[rfReplaceAll]);
    FAppend := Append;
    if FDest='' then
    begin
      // C:\a\b.mp4 ==> \a\b.mp4
      FDest := Copy(FSour,3,Length(FSour));
    end;
    FFTP.Connect;
  except
    on E: Exception do
      raise Exception.Create('连接FTP服务器异常：'+E.Message);
  end;
end;

procedure TFTPUploadThread.CreateFTPDir;
var
  slTmp,slFtp: TStringList;
  i,j: Integer;
  dir: string;
  exist: Boolean;
begin
  dir := '';
  slFtp := TStringList.Create;
  slTmp := TStringList.Create;
  try
    try
      slTmp.StrictDelimiter := True;
      slTmp.Delimiter := '\';
      slTmp.DelimitedText := FDest;
      FProgressInfo.FileName := slTmp[slTmp.Count-1];
      FFTP.TransferType := ftASCII;
      for I := 0 to slTmp.Count-3 do  //去尾 最后一级目录
      begin
        dir := dir+slTmp[i]+'\';
        FFTP.ExtListDir(slFtp,dir);
        exist := False;
        for j := 0 to slFtp.Count-1 do
        begin
          if Pos(slTmp[i+1],slFtp[j])>0 then
          begin
            exist := True;
            break;
          end;
        end;
        try
          if not exist then FFTP.MakeDir(dir+'\'+slTmp[i+1]+'\');
        except
          //控件暂时不支持utf-8
        end;
      end;
    except
      on E:Exception do
        raise Exception.Create('创建FTP目录异常：'+E.Message);
    end;
  finally
    slFtp.Free;
    slTmp.Free;
  end;
end;

destructor TFTPUploadThread.Destroy;
begin
  FFTP.Disconnect;
  FFTP.Free;
  inherited;
end;

procedure TFTPUploadThread.Execute;
begin
  inherited;
  if FFTP.Connected then
  begin
    CreateFTPDir;
    try
      FFTP.TransferType := ftBinary;
      FProgressInfo.MaxCount := FileSizeByName(FSour);
      FPos := FFTP.Size(FDest);
      FFTP.Put(FSour,FDest,FAppend,FPos);
    except
      on E:Exception do
        raise Exception.Create('上传文件异常：'+E.Message);
    end;
  end;
end;

procedure TFTPUploadThread.OnWork(ASender: TObject; AWorkMode: TWorkMode;
  AWorkCount: Int64);
var
  deltaTime: Int64;
begin
  //每1MB发一次进度
  if (AWorkMode=wmWrite) and (AWorkCount mod (1024*1024) = 0) then
  begin
    deltaTime := GetTickCount-FTime;
    if deltaTime <= 0 then Exit;
    FProgressInfo.ACount := FPos+AWorkCount;
    FProgressInfo.progress := FProgressInfo.ACount/FProgressInfo.MaxCount;
    FProgressInfo.speed := Format('%.2f',[1000*(AWorkCount-FCount)/(deltaTime*1024*1024)])+'MB/s';
    FCB(Handle,FProgressInfo);
    FTime := GetTickCount;
    FCount := AWorkCount;
  end;
end;

procedure TFTPUploadThread.OnWorkBegin(ASender: TObject; AWorkMode: TWorkMode;
  AWorkCountMax: Int64);
begin
  if AWorkMode=wmWrite then
  begin
    FProgressInfo.ACount := FPos;
    FProgressInfo.progress := FPos/FProgressInfo.MaxCount;
    FProgressInfo.speed := '0MB/s';
    FCB(Handle,FProgressInfo);
    FTime := GetTickCount;
    FCount := 0;
  end;
end;

procedure TFTPUploadThread.OnWorkEnd(ASender: TObject; AWorkMode: TWorkMode);
begin
  if AWorkMode=wmWrite then
  begin
    FProgressInfo.ACount := FProgressInfo.MaxCount;
    FProgressInfo.progress := 1;
    FProgressInfo.speed := '0MB/s';
    FCB(Handle,FProgressInfo);
  end;
end;

end.
