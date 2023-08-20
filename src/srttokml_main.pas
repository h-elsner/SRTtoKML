{********************************************************}
{                                                        }
{       Convert subtitles with telemetry to KML          }
{                                                        }
{       Copyright (c) 2023    Helmut Elsner              }
{                                                        }
{       Compiler: FPC 3.2.2   /  Lazarus 2.2.6           }
{                                                        }
{ Pascal programmers tend to plan ahead, they think      }
{ before they type. We type a lot because of Pascal      }
{ verboseness, but usually our code is right from the    }
{ start. We end up typing less because we fix less bugs. }
{           [Jorge Aldo G. de F. Junior]                 }
{********************************************************}

(*
Format SRT file from DJI Mini3 (example; data set per frame):

1
00:00:00,000 --> 00:00:00,033
<font size="28">SrtCnt : 1, DiffTime : 33ms
2023-06-30 14:13:05.282
[iso : 100] [shutter : 1/100.0] [fnum : 170] [ev : -1.3] [ct : 5288] [color_md : default] [focal_len : 240] [dzoom_ratio: 10000, delta:0],[latitude: 50.646244] [longitude: 11.377171] [rel_alt: 63.700 abs_alt: 303.645] </font>

2
00:00:00,033 --> 00:00:00,066
<font size="28">SrtCnt : 2, DiffTime : 33ms
2023-06-30 14:13:05.312
[iso : 100] [shutter : 1/100.0] [fnum : 170] [ev : -1.3] [ct : 5288] [color_md : default] [focal_len : 240] [dzoom_ratio: 10000, delta:0],[latitude: 50.646244] [longitude: 11.377171] [rel_alt: 63.700 abs_alt: 303.645] </font>

3
00:00:00,066 --> 00:00:00,100
<font size="28">SrtCnt : 3, DiffTime : 34ms
2023-06-30 14:13:05.346
[iso : 100] [shutter : 1/100.0] [fnum : 170] [ev : -1.3] [ct : 5288] [color_md : default] [focal_len : 240] [dzoom_ratio: 10000, delta:0],[latitude: 50.646244] [longitude: 11.377171] [rel_alt: 63.700 abs_alt: 303.645] </font>
...

================================================================================
History
2023-08-19 Idea and plan, GUI
2023-08-20 First version
*)

unit SRTtoKML_main;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls,
  StdCtrls, Buttons, XMLPropStorage, RegExpr;

type
  fpoint=record
    lat: string;
    lon: string;
    alt: string;
    date: string;
    time: string;
    v: boolean;
  end;

type

  { TForm1 }

  TForm1 = class(TForm)
    btnConvert: TBitBtn;
    btnClose: TBitBtn;
    btnSave: TBitBtn;
    ImageList1: TImageList;
    Memo1: TMemo;
    Memo2: TMemo;
    OpenDialog1: TOpenDialog;
    panTop: TPanel;
    SaveDialog1: TSaveDialog;
    Splitter1: TSplitter;
    XMLPropStorage1: TXMLPropStorage;
    procedure btnCloseClick(Sender: TObject);
    procedure btnConvertClick(Sender: TObject);
    procedure btnSaveClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
  private
    procedure KMLheader(f, dt: string; klist: TStringList);
  public

  end;

const
  latID='latitude: ';
  lonID='longitude: ';
  altID='abs_alt: ';
  selpar=']';
  selval=':';
  tab1=' ';
  tab2='  ';
  tab4='    ';

  xmlvers='<?xml version="1.0" encoding="UTF-8"?>';      {ID XML/GPX header}
  kmlvers='<kml xmlns="http://www.opengis.net/kml/2.2" xmlns:gx="http://www.google.com/kml/ext/2.2">';
  pmtag='Placemark>';
  doctag='Document>';
  aircrafticon='https://earth.google.com/images/kml-icons/track-directional/track-0.png';
  ColorTrack=clYellow;
  ColorWaypoints=clRed;
  WidthTrack='2';

var
  Form1: TForm1;

implementation

{$R *.lfm}

{$I SRTtoKML_de.inc}                                     {German GUI}
{.$I SRTtoKML_en.inc}                                    {English GUI}

{ TForm1 }

function ColorToKMLColor(const AColor: TColor): string;  {Google Farbcodierung}
begin
  Result:='FF'+IntToHex(ColorToRgb(AColor), 6);
end;

function write_nme(nm: string): string; inline;          {Set an "name" line tagged}
begin
  result:=tab2+'<name>'+nm+'</name>';
end;

function write_des(des: string): string;
begin
  result:=tab2+'<description>'+des+'</description>';
end;

procedure TForm1.KMLheader(f, dt: string; klist: TStringList);
begin
  klist.Add(xmlvers);
  klist.Add(kmlvers);
  klist.Add('<'+doctag);
  klist.Add(write_nme('SRTtoKML'));
  klist.Add(write_des(dt+' - '+ExtractFileName(f)));
  klist.Add('<Style id="Flightpath">');
  klist.Add(tab2+'<LineStyle>');
  klist.Add(tab4+'<color>'+ColorToKMLColor(ColorTrack)+'</color>');  {Color for track}
  klist.Add(tab4+'<width>'+WidthTrack+'</width>');
  klist.Add(tab2+'</LineStyle>');
  klist.Add(tab2+'<PolyStyle><color>'+ColorToKMLColor(ColorWaypoints)+'</color></PolyStyle>');  {Color for Waypoints}
  klist.Add(tab2+'<IconStyle><Icon><href>'+aircrafticon+'</href></Icon></IconStyle>');
  klist.Add('</Style>');
end;

procedure ClearFPoint(var p: fpoint);
begin
  p.lat:='';
  p.lon:='';
  p.alt:='';
  p.date:='';
  p.time:='';
  p.v:=false;
end;

procedure ValidateFPoint(var p: fpoint);
begin
  p.v:=false;
  if (p.lat<>'') and (P.lon<>'') and (p.alt<>'') and
     (p.date<>'') and (p.time<>'') then
    p.v:=true;
end;

function GetFPoint(s: string; var p: fpoint): boolean;
var
  sellist: TStringList;
  i: integer;
  re: TRegExpr;

begin
  sellist:=TStringList.Create;
  sellist.Delimiter:=selpar;
  sellist.StrictDelimiter:=true;
  result:=false;
  re:=TRegExpr.Create('[0-9]{4}-[0-9]{2}-[0-9]{2}');
  try
    if re.Exec(s) then begin                             {Get time}
      p.date:=s.Split([tab1])[0];
      p.time:=s.Split([tab1])[1];
      result:=true;
    end else begin
      if pos(selpar, s)>0 then begin                     {Get lat, lon, alt}
        sellist.DelimitedText:=s;
        for i:=0 to sellist.Count-1 do begin
          if pos(latID, sellist[i])>0 then begin
            p.lat:=sellist[i].Split([selval])[1];
          end;
          if pos(lonID, sellist[i])>0 then begin
            p.lon:=sellist[i].Split([selval])[1];
          end;
          if pos(altID, sellist[i])>0 then begin
            p.alt:=sellist[i].Split([selval])[2];        {abs_alt on second position}
            result:=true;
          end;
        end;
      end;
    end;
  finally
    sellist.Free;
    re.Free;
  end;
end;

procedure TForm1.btnConvertClick(Sender: TObject);
var
  kmllist, coolist: TStringList;
  i: integer;
  dp: fpoint;

begin
  if OpenDialog1.Execute then begin
    kmllist:=TStringList.Create;
    coolist:=TStringList.Create;
    Screen.Cursor:=crHourGlass;
    ClearFPoint(dp);
    try
      Memo1.Lines.Clear;
      Memo2.Lines.Clear;
      Memo1.Lines.LoadFromFile(OpenDialog1.FileName);    {Load SRT file}
      if Memo1.Lines.Count>100 then begin
        for i:=1 to 10 do begin                          {Get start point and first data set}
          if not GetFPoint(Memo1.Lines[i], dp) then
            continue;
          ValidateFPoint(dp);
          if dp.v then
            break;
        end;
        if dp.v then begin
          KMLheader(ChangeFileExt(OpenDialog1.FileName, ''), dp.date, kmllist);
          kmllist.Add('<'+pmtag);
          kmllist.Add(write_nme('Drone'));
          kmllist.Add(write_des(ExtractFileName(OpenDialog1.FileName)));
          kmllist.Add(tab2+'<styleUrl>#Flightpath</styleUrl>');
          kmllist.Add(tab2+'<gx:Track>');
          kmllist.Add(tab4+'<altitudeMode>absolute</altitudeMode>');
          kmllist.Add(tab4+'<extrude>1</extrude>');

          ClearFPoint(dp);
          for i:=0 to Memo1.Lines.Count-1 do begin
            GetFPoint(Memo1.Lines[i], dp);
            ValidateFPoint(dp);
            if dp.v then begin
              coolist.Add(tab4+'<gx:coord>'+dp.lon+tab1+dp.lat+tab1+dp.alt+'</gx:coord>');
              kmllist.Add(tab4+'<when>'+dp.date+'T'+dp.time+'Z</when>');
              dp.v:=false;
            end;
          end;

          if coolist.Count>10 then begin                 {The last point is valid and landing placemark}
            for i:=0 to coolist.Count-1 do
              kmllist.Add(coolist[i]);
            kmllist.Add('</gx:Track>');
            kmllist.Add('</'+pmtag);
            kmllist.Add('</'+doctag);
            kmllist.Add('</kml>');
            Memo2.Lines.Assign(kmllist);
          end;
        end;
      end;
    finally
      if Memo2.Lines.Count>1 then
        btnSave.Enabled:=true;                           {Save needed}
      Screen.Cursor:=crDefault;
      kmllist.Free;
      coolist.Free;
    end;

  end;
end;

procedure TForm1.btnSaveClick(Sender: TObject);
begin
  SaveDialog1.Filename:=ChangeFileExt(OpenDialog1.FileName, '.kml');
  if SaveDialog1.Execute then begin
    Memo2.Lines.SaveToFile(SaveDialog1.FileName);
    btnSave.Enabled:=false;                              {ID already saved}
  end;
end;

procedure TForm1.btnCloseClick(Sender: TObject);
begin
  if btnSave.Enabled then begin
    if MessageDlg(capDialog, errSave, mtConfirmation, [mbYes, mbNo],0) = mrYes then
      Close;
  end else
    Close;
end;

procedure TForm1.FormCreate(Sender: TObject);
begin
  caption:=appName;
  btnConvert.Caption:=capConvert;
  btnConvert.Hint:=hntConvert;
  btnClose.Caption:=capClose;
  btnClose.Hint:=hntClose;
  btnSave.Caption:=capSave;
  btnSave.Hint:=hntSave;
  OpenDialog1.Title:=titOpen;
  SaveDialog1.Title:=titSave;
  Memo1.Text:=hntConvert;
  Memo2.Text:=hntSave;
  btnSave.Enabled:=false;                                 {ID save not needed}
end;

end.

