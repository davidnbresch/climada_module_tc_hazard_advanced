function [hazard,elevation_save_file]=climada_ts_hazard_set(hazard,hazard_set_file,elevation_data,check_plot,verbose,elevation_save_file,decay_buffer_km,SLR_increment_m)
% climada storm surge TS hazard event set
% NAME:
%   climada_ts_hazard_set
% PURPOSE:
%   create a storm surge (TS) hazard event, based on an existing
%   tropical cyclone (TC) hazard event set and the SLOSH model
%   (http://www.nhc.noaa.gov/surge/slosh.php)
%
%   Either using ETOPO1 (horizontal resolution 1.9km, fast, default) or SRTM
%   (horizontal resolution90m, vertical accuracy about 1m, computationally
%   intensive) elevation data. Or use elevation as provided on input.
%
%   two steps:
%   1)  check wether we need to obtain bathymetry (calls etopo_get or
%       climada_srtm_get from module
%       https://github.com/davidnbresch/climada_module_elevation_models) or
%       elevation is provided (see elevation_data)
%   2)  convert all TC footprints into TS footprints, using the SLOSH
%       approach, see CORE_CONVERSION in code below for the conversion formula
%       (see also http://www.nhc.noaa.gov/surge/slosh.php)
%   3) apply an inland decay correction of 0.2 m per 1 km distance from the
%       coastline. Based on one single case study (2006). See note at the
%       bottom of this file, too.
%
%   If you set climada_global.parfor=1, both the gridding of elevation as
%   well as the event calculation will be parallelized for speedup.
%
%   Maximum surge height is 10m, hence any point with higher than 10m
%   elevation is not dealt with.
%
%   If hazard.distance2coast_km exists on input, surge heights for points
%   more than centroid_inland_max_dist_km inland (see PARAMETERS, usually
%   50km) are set to zero. Set hazard.distance2coast_km negative for ocean
%   points (climada convention) for them not to be excluded.
%
%   see tc_surge_TEST for a testbed for this code
%
%   ETOPO, see etopo_get and for the data
%       https://www.ngdc.noaa.gov/mgg/global/, doi:10.7289/V5C8276M
%   SRTM, see climada_srtm_get and for the data (usually fetched
%       automatically by climada_srtm_get) http://srtm.csi.cgiar.org
% CALLING SEQUENCE:
%   [hazard,elevation_save_file]=climada_ts_hazard_set(hazard,hazard_set_file,elevation_data,check_plot,verbose,elevation_save_file)
% EXAMPLE:
%   hazard_TC=climada_hazard_load('TCNA_today_small')
%   hazard_TS_ETOP=climada_ts_hazard_set(hazard_TC,'TCNA_today_small_TS','ETOPO',10)
%   hazard_TS_SRTM=climada_ts_hazard_set(hazard_TC,'TCNA_today_small_TS','SRTM', 10) % test SRTM (90m) elevation data
%   % add sea level rise (SLR of 1.23 m) to the global hazard:
%   climada_ts_hazard_set('GLB_0360as_TC_p_dist_decay','GLB_0360as_TS_p_dist_decay','ETOPO',0,0,'',[],1.23); % last parameter is SLR
% INPUTS:
%   hazard: an already existing tropical cyclone (TC) hazard event set (a
%       TC hazard structure). If hazard.distance2coast_km exists, only
%       points closer than 50km inland are treated (and all ocean points).
%       > prompted for if not given (for .mat file containing a TC hazard event set)
%       Note: if hazard.elevation_m exists on input, this elevation
%       information is used (elevation_data is ignored), unless
%       elevation_data is set to ='ETOPO' or ='SRTM', in which case
%       hazard.elevation_m is replaced by the ETOPO1 or SRTM data.
%       The variable hazard is modified on output (saves a lot of memory).
%   hazard_set_file: the name of the newly created storm surge (TS) hazard
%       event set (if ='NO_SAVE' or ='NOSAVE', the hazard is just returned, not saved)
%       > promted for if not given
% OPTIONAL INPUT PARAMETERS:
%   elevation_data: if a scalar, take elevation (or bathymetry) from etopo
%       (needs module etopo). If =1, save bathymetry in a .mat file (speeds up
%       subsequent calls), if =0 do not save bathymetry (default)
%       If elevation_data is a structure with the fields lon(i), lat(i),
%       elevation_m(i) and centroid_ID(i), check for centroid IDs being the
%       same as in hazard.centroid_ID and then just 'attach' the elevation
%       to hazard (i.e. hazard.elevation_m=elevation_data.elevation_m)
%       Note: if hazard.elevation_m exists on input, this elevation
%       information is used.
%       ='SRTM': use SRTM (horizontal resolution 90m) elevation data. Quite
%       time consuming, but much more precise, e.g. setting
%       hazard.fraction. This ignores any field hazard.elevation_m
%       ='ETOPO': force the use of ETOPO1 (horizontal resolution 1.9km)
%       elevation data. Ignore any field hazard.elevation_m
%   check_plot: =1, do show check plots, =0: no plots (default)
%       if =X, use range 0..Xm in plot of elevation
%       if negative, also show mapping for SRTM re-gridding (plot takes a
%       lot of time, only set this for small TEST areas, please)
%   verbose: =1, verbose mode (default), =0: almost silent
%       =2: SUPERTEST mode for Barisal, Bangladesh, hence run:
%           entity=climada_nightlight_entity('Bangladesh','Barisal')
%           tc_track=climada_tc_track_load('nio_hist')
%           hazard_TC=climada_tc_hazard_set(tc_track,'BGD_Barisal_TC_hist',entity);
%           hazard_SRTM=climada_ts_hazard_set(hazard_TC,'_BGD_Barisal_TS_hist','SRTM',2,2);
%           hazard_ETOP=climada_ts_hazard_set(hazard_TC,'_BGD_Barisal_TS_hist',[]    ,2,2);
%           EDS   =climada_EDS_calc(entity,hazard_TC);  EDS(1).annotation_name='wind';
%           EDS(2)=climada_EDS_calc(entity,hazard_SRTM);EDS(2).annotation_name='surge, SRTM';
%           EDS(3)=climada_EDS_calc(entity,hazard_ETOP);EDS(3).annotation_name='surge, ETOPO';
%           EDS(4)=climada_EDS_combine(EDS);
%           [DFC,fig,legend_str,legend_handle] =climada_EDS_DFC(EDS);
%           em_data=emdat_read('','BGD','-TC',1,1);
%           [legend_str,legend_handle]=emdat_barplot(em_data,'','','',legend_str,legend_handle)
%   elevation_save_file: the save file (with full path) for either ETOPO or
%       SRTM elevation. Truly expert mode, i.e the user is responsible for
%       content of this file matching the needs of the calculation.
%       Standard procedure is to first run climada_ts_hazard_set for a set
%       of centroids once and then use the same elevation data in
%       subsequent calls (with exactly the same centroids!)
%   decay_buffer_km: define threshold distance to coast inland
%       for the inland decay to kick in. Set around 0.1 to 0.5 times the
%       horizontal resolution of the hazard set to keep decay effects on 
%       the centroids closest to the coast small. decay_buffer_km is subtracted
%       from distance2coast_km. default = 3 (for a resolution of 10km)
%   SLR_increment_m: an increment to add sea level (SLR) rise, in meters.
%       Default=0 (obviously)
% OUTPUTS:
%   hazard: a hazard event set, see core climada doc
%       also written to a .mat file (see hazard_set_file)
%       NOTE: for memory allocation reasons, the input hazard is used and
%       modified to create the output hazard
%   elevation_save_file: the file with the elevation data, to be used for
%       subsequent calls with exactly the same centroids, see parameter
%       elevation_save_file. For ETOPO, the variable stored is named ETOPO,
%       for SRTM it is named SRTM to avoid confusion.
% MODIFICATION HISTORY:
% david.bresch@gmail.com, 20140421
% david.bresch@gmail.com, 20141017, module path relative
% david.bresch@gmail.com, 20141026, save_bathymetry_flag
% david.bresch@gmail.com, 20150106, elevation_data
% david.bresch@gmail.com, 20160516, elevation_data single precision allowed (as eg from SRTM)
% david.bresch@gmail.com, 20160525, better error messaging for ETOPO issues
% david.bresch@gmail.com, 20160529, renamed to climada_ts_hazard_set and tc_surge_hazard_create deleted
% david.bresch@gmail.com, 20161009, strcmpi used
% david.bresch@gmail.com, 20170523, > in save fprintf to identify latest version
% david.bresch@gmail.com, 20170806, elevation_save_file stored in global data dir, not within module
% david.bresch@gmail.com, 20171103, using SRTM data introduced
% eberenz@posteo.eu,      20171107, prevent out-of-bounds error for etopo_get(bathy_coords)
% david.bresch@gmail.com, 20180101, for SRTM mapping, use a bit wider a distance
% david.bresch@gmail.com, 20180104, elevation_save_file and centroid_inland_max_dist_km
% david.bresch@gmail.com, 20180206, height_decay_m_km added
% eberenz@posteo.eu, 20180209, decay_buffer_km added
% eberenz@posteo.eu, 20180212, height_decay_m_km set to 0.2 m/km, decay_buffer_km default set to 3 km
% david.bresch@gmail.com, 20180810, SLR_increment_m added
%-

global climada_global
if ~climada_init_vars,return;end % init/import global variables

% poor man's version to check arguments
if ~exist('hazard','var'),hazard=[];end
if ~exist('hazard_set_file','var'),hazard_set_file='';end
if ~exist('elevation_data','var'),elevation_data=[];end
if ~exist('check_plot','var'),check_plot=0;end
if ~exist('verbose','var'),verbose=1;end
if ~exist('elevation_save_file','var'),elevation_save_file='';end
if ~exist('decay_buffer_km','var'),decay_buffer_km=[];end % spatially delays inland decay by X km 
if ~exist('SLR_increment_m','var'),SLR_increment_m=[];end % incremen to mimic SLR

% PARAMETERS
%
%module_data_dir=[fileparts(fileparts(mfilename('fullpath'))) filesep 'data'];
%if ~isdir(module_data_dir),mkdir(fileparts(module_data_dir),'data');end % create the data dir, should it not exist (no further checking)
%
% the following setting reduces computation time substantially
centroid_inland_max_dist_km=50; % inland distance (from any coast, in km) we still treat
%
% to avoid many spurious heights, we set surges smaller than to zero
height_precision_m=0.05; % in m, up to 5 cm ignored
%
% inland decay of surge height (in meters) per kilometer (km) inland
height_decay_m_km=0.2; % decay in m per km, see note at bottom. set to value between 0.2 and 0.4 
%
if isempty(decay_buffer_km),decay_buffer_km=3;end
if isempty(SLR_increment_m),SLR_increment_m=0;end
%
regrid_check_plot=0; % the check plot of the regridding of SRTM, see climada_regrid, very time consuming plot
if check_plot<0,regrid_check_plot=1;check_plot=abs(check_plot);end

%%%%%%%%%%%%%%%%%%%%%%%%
if isfield(hazard,'distance2coast_km')
    fprintf('WARNING: height_decay_m_km added, not fully tested yet (if you use distance2coast_km)\n')
end
%%%%%%%%%%%%%%%%%%%%%%%%

if strcmpi(elevation_data,'SRTM')
    elevation_data=[];
    use_SRTM=1; % use high-res SRTM data (90m)
    if isfield(hazard,'elevation_m'),hazard=rmfield(hazard,'elevation_m');end % force re-calc
elseif strcmpi(elevation_data,'ETOPO')
    use_SRTM=0; % use default (fast) ETOPO data (1.9km)
    if isfield(hazard,'elevation_m'),hazard=rmfield(hazard,'elevation_m');end % force re-calc
else
    use_SRTM=0; % use default (fast) ETOPO data (1.9km)
end
if ~isstruct(elevation_data),elevation_data=[];end % make empty

hazard=climada_hazard_load(hazard);
if isempty(hazard),return;end
if isfield(hazard,'fraction'),hazard=rmfield(hazard,'fraction');end

% % prompt for TC hazard event set if not given
% if isempty(hazard) % local GUI
%     TC_hazard_set_file=[climada_global.data_dir filesep 'hazards' filesep '*.mat'];
%     [filename, pathname] = uigetfile(TC_hazard_set_file, 'Select a TC hazard event set:');
%     if isequal(filename,0) || isequal(pathname,0)
%         return; % cancel
%     else
%         TC_hazard_set_file=fullfile(pathname,filename);
%     end
%     load(TC_hazard_set_file);
% end

if verbose==2
    % SUPER TEST mode
    pos=find(hazard.lon>90 & hazard.lon<90.2 & hazard.lat>21.77 & hazard.lat<21.97);
    fprintf('SUPERTEST, only % i of %i centroids in hard-wired region [90 90.2 21.77 21.97]\n',length(pos));
    hazard.lon=hazard.lon(pos);
    hazard.lat=hazard.lat(pos);
    if isfield(hazard,'centroid_ID'),hazard.centroid_ID=hazard.centroid_ID(pos);end
    hazard.intensity=hazard.intensity(:,pos);
end

% prompt for hazard_set_file if not given
if isempty(hazard_set_file) % local GUI
    hazard_set_file=[climada_global.data_dir filesep 'hazards' filesep 'TS_hazard.mat'];
    [filename, pathname] = uiputfile(hazard_set_file, 'Save new TS hazard event set as:');
    if isequal(filename,0) || isequal(pathname,0)
        return; % cancel
    else
        hazard_set_file=fullfile(pathname,filename);
    end
end

% complete path, if missing
[fP,fN,fE]=fileparts(hazard_set_file);
if isempty(fE),fE='.mat';end
if isempty(fP),fP=climada_global.hazards_dir;end
hazard_set_file=[fP filesep fN fE];

% 1) try to obtain the elevation in different ways
% ------------------------------------------------

if ~isfield(hazard,'elevation_m') && ~isempty(elevation_data)
    % first, use data as provided in elevation_data
    if isfield(elevation_data,'centroid_ID')
        if length(elevation_data.centroid_ID)==length(hazard.centroid_ID)
            if sum(elevation_data.centroid_ID-hazard.centroid_ID)==0
                % elevation provided at hazard centroids
                hazard.elevation_m=elevation_data.elevation_m;
            end
        end
    end
end

if ~isfield(hazard,'elevation_m')
    % if elevation_data is empty, use the elevation module
    
    if ~isempty(elevation_data)
        % if elevation_data provided, we should not get here
        fprintf('Warning: elevation_data failed, using ETOPO\n');
    end
    
    if isempty(which('etopo_get')) % check for elevation module (both ETOPO1 and SRTM)
        fprintf(['WARNING: install climada elevation module first. Please download ' ...
            '<a href="https://github.com/davidnbresch/climada_module_elevation_models">'...
            'climada_module_elevation_models</a> from Github.\n'])
        fprintf('Note: code %s continues, but might encounter problems\n',mfilename);
    end
    
    % prep the region we need (rectangular region encompassing the hazard centroids)
    centroids_rect=[min(hazard.lon) max(hazard.lon) min(hazard.lat) max(hazard.lat)];
    
    % 1) create the bathymetry file
    % -----------------------------
    
    if use_SRTM % SRTM
        
        % define save filename
        [~,fN]=fileparts(hazard_set_file);
        fN=strrep(strrep(fN,'_prob',''),'_hist','');
        if isempty(elevation_save_file),elevation_save_file=...
                [climada_global.results_dir filesep strrep(['_SRTM_' fN],'__','_') '.mat'];end
        
        if exist(elevation_save_file,'file')
            fprintf('< reading SRTM from %s (delete to re-create)\n',elevation_save_file)
            load(elevation_save_file)
            hazard.elevation_m=SRTM.elevation_m;
        else
            
            bb=0.1; % 0.1 degree of bathy outside centroids (to allow for smooth interp)
            bathy_coords=[centroids_rect(1)-bb centroids_rect(2)+bb centroids_rect(3)-bb centroids_rect(4)+bb];
            
            SRTM=climada_srtm_get(bathy_coords);
            
            % prepare inputs for climada_regrid
            SRTM.lon=reshape(SRTM.x,1,numel(SRTM.x));
            SRTM.lat=reshape(SRTM.y,1,numel(SRTM.y));
            SRTM.val=reshape(SRTM.h,1,numel(SRTM.h));
            SRTM=rmfield(SRTM,'x');SRTM=rmfield(SRTM,'y');SRTM=rmfield(SRTM,'h');
            
            % reduce area covered by SRTM to what we really need (still a rect)
            pos= SRTM.lon > bathy_coords(1) & SRTM.lon < bathy_coords(2) & SRTM.lat > bathy_coords(3) & SRTM.lat < bathy_coords(4);
            SRTM.lon=SRTM.lon(pos);
            SRTM.lat=SRTM.lat(pos);
            SRTM.val=SRTM.val(pos);
            
            % we currently run the mapping for ALL centroids, knowing that
            % only the ones close to the coast and lower than 10m will be
            % used - but this way, we obtain a fully coherent mapping. And
            % since the number of SRTM points is usually >> centroids, the
            % exact number of centroids is not the main driver of performance
            arr_target.lon=hazard.lon;arr_target.lat=hazard.lat;
            dd=abs(diff(hazard.lon));arr_target.max_dist=min(dd(dd>0))/2*sqrt(2); % pass on max distance to consider
            [arr_target,SRTM]=climada_regrid(SRTM,arr_target,regrid_check_plot,1); % only plot for SUPERCHECK
            SRTM.elevation_m=arr_target.val; % to copy in SRTM for save
            clear arr_target % free up memory
            SRTM.centroid_i=SRTM.target_i;SRTM=rmfield(SRTM,'target_i'); % better name for local use
            
            if ~contains(elevation_save_file,'NOSAVE') && ~contains(elevation_save_file,'NO_SAVE')
                fprintf('> saving SRTM for speedup in subsequent calls as %s (you might later delete this file)\n',elevation_save_file);
                save(elevation_save_file,'SRTM');
            else
                %save(elevation_save_file,'SRTM'); % in case you enable this, also enable next line:
                %fprintf('!!! WARNING: delete %s ASAP (subsequent calls with otherwise use same SRTM area) !!!\n',elevation_save_file);
            end
            
            hazard.elevation_m=SRTM.elevation_m;
            
        end % exist(elevation_save_file,'file')
        
        if check_plot
            if check_plot>1
                mav=check_plot;
                fprintf('> using vertical scale 0..%im in SRTM elevation plot\n',check_plot);
            else
                mav=max(hazard.elevation_m);
            end
            marker_size=4;
            figure('Name',[mfilename ' SRTM elevation']);cmap=colormap;
            plotclr(SRTM.lon,SRTM.lat,SRTM.val,'s',marker_size,1,0,mav,cmap,0,0);hold on;
            plotclr(hazard.lon,hazard.lat,full(hazard.elevation_m),'s',marker_size,1,0,mav,cmap,0,0);
            plot(hazard.lon,hazard.lat,'.r','MarkerSize',1);
            axis equal
            xlim_tmp=xlim;ylim_tmp=ylim;
            hold on;climada_plot_world_borders;
            xlim(xlim_tmp);ylim(ylim_tmp);
            title('SRTM elevation [m]')
        end % check_plot
        
        if isfield(hazard,'windfield_comment'),hazard=rmfield(hazard,'windfield_comment');end % remove
        hazard.surgefield_comment=sprintf('created based on TC using proxy surge height and SRTM %s (mapping/value took %f/%f sec.)',...
            SRTM.filename,SRTM.map_time,SRTM.val_time);
        
    else % ETOPO
        
        bb=1; % 1 degree of bathy outside centroids (to allow for smooth interp)
        bathy_coords=[centroids_rect(1)-bb centroids_rect(2)+bb centroids_rect(3)-bb centroids_rect(4)+bb];
        
        % cut the bathymtery data out of the global topography dataset
        
        % file the bathymetry gets stored in ( might not be used later on, but
        % saved to speed up re-creation of the TS hazard event set
        [~,fN]=fileparts(hazard_set_file);
        fN=strrep(strrep(fN,'_prob',''),'_hist','');
        if isempty(elevation_save_file),elevation_save_file=...
                [climada_global.results_dir filesep strrep(['_ETOPO_' fN],'__','_') '.mat'];end
        
        if ~exist(elevation_save_file,'file')
            
            % bathy_coords =[-179   179  -60.9500   89] % 20171025, dnb, for TS global
            % 20171107 se, flexible solution for TS global (to prevent out-of-bounds error for etopo_get)
            if le(bathy_coords(1),-180), bathy_coords(1) = -179; end
            if ge(bathy_coords(2), 180), bathy_coords(2) =  179; end
            if le(bathy_coords(3), -90), bathy_coords(3) =  -60.9500; end
            if ge(bathy_coords(4),  90), bathy_coords(4) =   89; end
            
            BATI=etopo_get(bathy_coords,check_plot);
            if isempty(BATI),hazard=[];
                return
            end % error messages from etopo_get already
            
            if (~contains(elevation_save_file,'NOSAVE') && ~contains(elevation_save_file,'NO_SAVE'))
                fprintf('> saving ETOPO for speedup in subsequent calls as %s (you might later delete this file)\n',elevation_save_file);
                save(elevation_save_file,'BATI');
            else
                %save(elevation_save_file,'SRTM'); % in case you enable this, also enable next line:
                %fprintf('!!! WARNING: delete %s ASAP (subsequent calls with otherwise use same SRTM area) !!!\n',elevation_save_file);
            end
            
        else
            fprintf('< reading ETOPO from %s\n',elevation_save_file);
            load(elevation_save_file); % contains BATI
        end
        
        hazard.elevation_m=interp2(BATI.x,BATI.y,BATI.h,hazard.lon,hazard.lat);
        if isfield(hazard,'onLand'),hazard=rmfield(hazard,'onLand');end % re-create to be on the safe side
        hazard.onLand=hazard.lon.*0+1; % allocate
        hazard.onLand(hazard.elevation_m<0)=0; % water points
        hazard.elevation_m=max(hazard.elevation_m,0); % only points above sea level
        
        if check_plot
            if check_plot>1
                mav=check_plot;
                fprintf('> using vertical scale 0..%im in ETOPO elevation plot\n',check_plot);
            else
                mav=max(hazard.elevation_m);
            end
            marker_size=10;
            figure('Name',[mfilename ' ETOPO elevation']);cmap=colormap;
            plotclr(BATI.x,BATI.y,BATI.h,'s',marker_size,1,0,mav,cmap,0,0);hold on;
            plotclr(hazard.lon,hazard.lat,full(hazard.elevation_m),'s',marker_size,1,0,mav,cmap,0,0);
            plot(hazard.lon,hazard.lat,'.r','MarkerSize',1);
            axis equal
            xlim_tmp=xlim;ylim_tmp=ylim;
            hold on;climada_plot_world_borders;
            xlim(xlim_tmp);ylim(ylim_tmp);
            title('ETOPO elevation [m]')
        end % check_plot
        
        if isfield(hazard,'windfield_comment'),hazard=rmfield(hazard,'windfield_comment');end % remove
        if exist('BATI','var')
            hazard.surgefield_comment=sprintf('created based on TC using proxy surge height and ETOPO bathymetry %s',BATI.sourcefile);
        else
            hazard.surgefield_comment=sprintf('created based on TC using proxy surge height and elevation_m');
        end
        
    end % use_SRTM
    
end

% 2) create the storm surge (TS) hazard event set
% -----------------------------------------------

% start from the 'mother' TC hazard event set

hazard.peril_ID='TS'; % replace TC with TS
hazard.units='m'; % store the SI unit of the hazard intensity
hazard.comment=sprintf('TS hazard event set, generated %s',datestr(now));

% map windspeed onto surge height (the CORE_CONVERSION, see at botton of file, too)
% ===============================
arr_nonzero=find(hazard.intensity); % to avoid de-sparsify all elements
hazard.intensity(arr_nonzero)=0.1023*(max(hazard.intensity(arr_nonzero)-26.8224,0))+1.8288+SLR_increment_m; % m/s converted to m surge height, 20180810: +SLR_increment_m

% subtract elevation above sea level from surge height
t0         = clock;
n_events   = size(hazard.intensity,1);
n_centroids= size(hazard.intensity,2);

% set distance2coast to 0 below threshold
if decay_buffer_km>0 && isfield(hazard,'distance2coast_km')
    hazard.distance2coast_km = max(hazard.distance2coast_km - decay_buffer_km,0); % subtract decay buffer from distance
end

% as the innermost loop is vectorized, it shall be the one repeated most:

if use_SRTM % SRTM
    
    % using SRTM; precise, but slow
    
    if isfield(hazard,'distance2coast_km')
        if verbose,fprintf('restricting to centroids in elevation range ]0..10] m and closer than %i km to coast with a decay of %2.1fm/km inland\n',...
                centroid_inland_max_dist_km,height_decay_m_km);end
        elev_point_pos=find(hazard.elevation_m>0 & hazard.elevation_m<10 & hazard.distance2coast_km<centroid_inland_max_dist_km);
        
        inland_decay=max(hazard.distance2coast_km*height_decay_m_km,0);
        inland_decay=inland_decay(elev_point_pos);
    else
        if verbose,fprintf('restricting to centroids in elevation range ]0..10] m\n');end % init, see terminate below
        elev_point_pos=find(hazard.elevation_m>0 & hazard.elevation_m<10);
        inland_decay=elev_point_pos*0; % set to zero
    end
    
    n_eff_centroids=length(elev_point_pos);
    
    hazard.fraction=spones(hazard.intensity); % init
    
    intensity=hazard.intensity(:,elev_point_pos); % init temp array
    fraction=spones(intensity); % init temp array
    
    SRTM_centroid_i=SRTM.centroid_i;
    SRTM_val=SRTM.val;
    
    if climada_global.parfor
        
        fprintf('generating %i surge fields at %i low-laying/coastal (of total %i) centroids (parfor) ...',n_events,n_eff_centroids,n_centroids);
        parfor centroid_ii=1:n_eff_centroids
            
            centroid_i=elev_point_pos(centroid_ii); % real i
            
            SRTM_val_tmp=double(SRTM_val(SRTM_centroid_i==centroid_i));
            n_points=length(SRTM_val_tmp);
            
            if sum(SRTM_val_tmp)>0
                
                intensity_tmp=intensity(:,centroid_ii); % only at elevated points
                fraction_tmp =fraction( :,centroid_ii); % only at elevated points
                
                arr_i=find(intensity_tmp); % non-zero intensity
                
                for event_ii=1:length(arr_i) % loop over non-zero surge points
                    
                    event_i=arr_i(event_ii); % real i
                    
                    surge_height=max(intensity_tmp(event_i)-SRTM_val_tmp,0);
                    n_nonzeros=length(find(surge_height>0));
                    
                    if n_nonzeros>0
                        intensity_tmp(event_i)=sum(surge_height)/n_nonzeros; % average height
                        fraction_tmp( event_i)=n_nonzeros/n_points; % fraction of non-zero points within centroid
                    else
                        intensity_tmp(event_i)=0;
                        fraction_tmp( event_i)=0;
                    end
                    
                end % event_ii
                
                %intensity(:,centroid_ii)=intensity_tmp; % until 20180206
                intensity(:,centroid_ii)=max(intensity_tmp-inland_decay(centroid_ii),0);
                fraction( :,centroid_ii)=fraction_tmp;
                
            end % sum(SRTM_val_tmp)>0
            
        end % centroid_ii
        fprintf(' done\n');
        
        clear surge_height % to avoid Warning by parser, it said:
        % The temporary variable surge_height will be cleared at the
        % beginning of each iteration of the parfor loop. Any value
        % assigned to it before the loop will be lost.  If surge_height is
        % used before it is assigned in the parfor loop, a runtime error
        % will occur.
        
    else
        
        fprintf('generating %i surge fields at %i low-laying/coastal (of total %i) centroids\n',n_events,n_eff_centroids,n_centroids);
        if verbose,climada_progress2stdout;end % init, see terminate below
        
        for centroid_ii=1:n_eff_centroids
            
            centroid_i=elev_point_pos(centroid_ii); % real i
            
            SRTM_val_tmp=double(SRTM_val(SRTM_centroid_i==centroid_i));
            n_points=length(SRTM_val_tmp);
            
            if sum(SRTM_val_tmp)>0
                
                intensity_tmp=intensity(:,centroid_ii); % only at elevated points
                fraction_tmp =fraction( :,centroid_ii); % only at elevated points
                
                arr_i=find(intensity_tmp); % non-zero intensity
                
                for event_ii=1:length(arr_i) % loop over non-zero surge points
                    
                    event_i=arr_i(event_ii); % real i
                    
                    surge_height=max(intensity_tmp(event_i)-SRTM_val_tmp,0);
                    n_nonzeros=length(find(surge_height>0));
                    
                    if n_nonzeros>0
                        intensity_tmp(event_i)=sum(surge_height)/n_nonzeros; % average height
                        fraction_tmp( event_i)=n_nonzeros/n_points; % fraction of non-zero points within centroid
                    else
                        intensity_tmp(event_i)=0;
                        fraction_tmp( event_i)=0;
                    end
                    
                end % event_ii
                
                %intensity(:,centroid_ii)=intensity_tmp; % until 20180206
                intensity(:,centroid_ii)=max(intensity_tmp-inland_decay(centroid_ii),0);
                fraction( :,centroid_ii)=fraction_tmp;
                
                if verbose,climada_progress2stdout(centroid_ii,n_eff_centroids,100,'centroids');end % update
                
            end % sum(SRTM_val_tmp)>0
            
        end % centroid_ii
        if verbose,climada_progress2stdout(0);end % terminate
        
    end % climada_global.parfor
    
    hazard.intensity(:,elev_point_pos)=intensity; clear intensity
    hazard.fraction( :,elev_point_pos)=fraction; clear fraction
    hazard.intensity(:,hazard.elevation_m>=10)=0; % clear high ground
    
    hazard.intensity=max(hazard.intensity,0); % avoid negative
    hazard.intensity(hazard.intensity>10)=10; % avoid heights >10m
    
else % ETOPO
    
    if isfield(hazard,'distance2coast_km')
        if verbose,fprintf('restricting to centroids in elevation range ]0..10] m and closer than %i km to coast with a decay of %2.1fm/km inland\n',...
                centroid_inland_max_dist_km,height_decay_m_km);end
        inland_decay=max(hazard.distance2coast_km*height_decay_m_km,0);
        inland_decay(hazard.elevation_m>0 & hazard.distance2coast_km>centroid_inland_max_dist_km)=100; % large decay to set to zero
    else
        if verbose,fprintf('restricting to centroids in elevation range ]0..10] m\n');end % init, see terminate below
        inland_decay=hazard.elevation_m*0; % set to zero
        inland_decay(hazard.elevation_m>10)=100;  % large decay to set to zero
    end
    
    % using ETOPO, fast, but coarse
    if n_events<n_centroids % loop over events, since less events than centroids
        
        if verbose,climada_progress2stdout;end % init, see terminate below
        
        for event_i=1:n_events
            arr_i=find(hazard.intensity(event_i,:)); % to avoid de-sparsify all elements
            hazard.intensity(event_i,arr_i)=max(hazard.intensity(event_i,arr_i)...
                -double(hazard.elevation_m(arr_i))-height_precision_m-inland_decay(arr_i),0); % since 20180206
            %   -double(hazard.elevation_m(arr_i))-height_precision_m,0); % 20160516 double(.) until 20180206
            
            if verbose,climada_progress2stdout(event_i,n_events,100,'events');end % update
            
        end % event_i
        
    else % loop over centroids, since less centroids than events
        
        if verbose,climada_progress2stdout;end % init, see terminate below
        
        for centroid_i=1:n_centroids
            arr_i=find(hazard.intensity(:,centroid_i)); % to avoid de-sparsify all elements
            hazard.intensity(arr_i,centroid_i)=max(hazard.intensity(arr_i,centroid_i)...
                -double(hazard.elevation_m(centroid_i))-height_precision_m-inland_decay(centroid_i),0); % since 20180206
            %   -double(hazard.elevation_m(centroid_i))-height_precision_m,0); % 20160516 double(.) until 20180206
            
            if verbose,climada_progress2stdout(centroid_i,n_centroids,100,'centroids');end % update
            
        end % event_i
        
    end % n_events<n_centroids
    if verbose,climada_progress2stdout(0);end % terminate
    
end % use_SRTM

t_elapsed = etime(clock,t0);
msgstr    = sprintf('generating %i surge fields took %3.2f min (%3.2f sec/event)',n_events,t_elapsed/60,t_elapsed/n_events);
fprintf('%s\n',msgstr);
hazard.creation_comment = msgstr;

if isfield(hazard,'distance2coast_km') % remove all surge heights for points more than centroid_inland_max_dist_km inland
    hazard.intensity(:,hazard.distance2coast_km>centroid_inland_max_dist_km)=0; % clear inland
end

if isfield(hazard,'filename'),hazard.filename_source=hazard.filename;end
hazard.intensity=sparse(hazard.intensity); % sparsify (to be sure)
if ~isfield(hazard,'fraction'),hazard.fraction=spones(hazard.intensity);end % fraction 100%

hazard.filename=hazard_set_file;
hazard.date=datestr(now);
hazard.matrix_density=nnz(hazard.intensity)/numel(hazard.intensity);
if ~isfield(hazard,'orig_event_count') % fix a minor issue with some hazard sets
    if isfield(hazard,'orig_event_flag')
        fprintf('field hazard.orig_event_count inferred from hazard.orig_event_flag\n')
        hazard.orig_event_count=sum(hazard.orig_event_flag);
    else
        fprintf('WARNING: no field hazard.orig_event_flag\n')
    end
end

if ~contains(hazard_set_file,'NO_SAVE') && ~contains(hazard_set_file,'NOSAVE')
    fprintf('> saving TS surge hazard set as %s\n',hazard_set_file);
    save(hazard_set_file,'hazard',climada_global.save_file_version);
end

if verbose,fprintf('TS: max(max(hazard.intensity))=%f\n',full(max(max(hazard.intensity))));end % a kind of easy check

if check_plot
    figure('Name',[mfilename ' max intens']);
    climada_hazard_plot(hazard,0); % show max surge over ALL events
    
    figure('Name',[mfilename ' histogram']);
    nzp=hazard.fraction>0;
    subplot(2,1,1)
    hist(hazard.fraction(nzp))
    title('hazard.fraction')
    subplot(2,1,2)
    %nzp=hazard.intensity>0;
    hist(hazard.intensity(nzp))
    title('hazard.intensity')
    set(gcf,'Color',[1 1 1])
end % check_plot

end % climada_ts_hazard_set

% % =====================================
% % wind speed to surge height conversion (CORE_CONVERSION)
% % =====================================
%
% % see also http://www.nhc.noaa.gov/surge/slosh.php)
%
% % uncomment one level, then copy/paste below into MATLAB command window
% % to run, i.e. to show the conversion fucntion as used above
%
% mph2ms=0.44704;
% f2m=0.3048;
%
% % the points read from the SLOSH graph
% v0=60*mph2ms;
% v1=140*mph2ms;
% s0=6*f2m;
% s1=18*f2m;
%
% % the parameters for the linear function
% a=(s1-s0)/(v1-v0)
% s0
% v0
%
% figure('Name','windspeed to surge height conversion','Color',[1 1 1])
% hold on
% v=20:100;       plot(v,          a*(v-v0)          +s0,'-r','LineWidth' ,3);
% vmph=60:20:140; plot(vmph*mph2ms,a*(vmph*mph2ms-v0)+s0,'.b','MarkerSize',10);
% legend('conversion','SLOSH points')
% xlabel('wind speed [m/s]')
% ylabel('surge height [m]')

% note on decay inland (to height_decay_m_km):
% --------------------------------------------
% Quotes:
% "To determine the maximum distance inland a storm surge may travel we
% note that historically the maximum height of a storm surge ever recorded
% is believed to have been between 13 and 15 m [1]. If we take the latter
% value and assume a distance decay factor of 0.3 meters per kilometer
% (Brecht et al., 2012) we estimate that the maximum threshold inland
% distance is around 50 km [2]. [...]
%
% [1] This was due to the Tropical Cyclone Mahina, a storm with sustained
% winds in excess of 280 km/h and struck Bathurst Bay, Australia on March
% 5, 1899.
%
% [2] For example, evidence for the storm surge for Hurricane Katrina was
% found up to 20 km inland (Fritz et al., 2007) and close to 50 km for
% Hurricane Ike (Forbes et al., 2011)."
% (Elliott et al. 2015)
%
% "As a surge moves inland, its height is diminished. The rate of decay 
% depends largely on terrain and surface features, as well as factors specific 
% to the storm generating the wave. In a case study on storm surges, 
% Nicholls (2006) uses a distance decay factor of 0.2 to 0.4 m per kilometer 
% that can be applied to wave heights in relatively flat coastal plains. 
% For this analysis, we use an intermediate value (0.3 m per 1 km distance 
% from the coastline) to estimate the wave height for each inland cell."
% (Brecht et al. 2012)
%
% Und hier noch als Wuerdigung der holistischen Sicht:
% "Controls on flooding Storm surge induced by tropical cyclones depends greatly on coastal geometries, including topography, local shoreline configurations and depth, and individual tropical cyclone characteristics ??? predominantly the wind speed, storm size and landfall location. The storm???s forward motion, angle of approach, and atmospheric pressure drop also influence surge generation. Tidal range and storm timing with the tide; the increase in water level, owing to the presence and local behaviour of shoaling waves; and river discharge and rainfall-driven runoff also contribute to flooding. However, in coastal regions that experience the most extreme tropical cyclone flooding, the greatest elevated water levels are largely due to wind-driven storm surge. Using a linearized momentum conservation argument, for which bottom friction and other external forces are neglected, it can be shown that wind surge is proportional to U2 * W/h, where U is wind speed, W is the distance over which the wind blows in the same direction, and h is the mean depth over the region where the wind blows."
% (Woodruff et al. 2013, citing and summarising Resio & Westerink, 2008)
%
% References:
% Brecht, H., Dasgupta, S., Laplante, B., Murray, S., Wheeler, D., 2012. Seal-level rise and storm surges: high stakes for a small number of developing countries. The Journal of Environment and Development 21, 120???138.
% Elliott et al., 2015. The local impact of typhoons on economic activity in China: A view from outer space. Journal of Urban Economics 88, 50-66.
% Nicholls, R. J., 2006. Storm surges in coastal areas. Natural disaster hot spots case studies. Washington, DC: World Bank. (Book?)
% Resio, D. T. & Westerink, J. J, 2008. Modeling the physics of storm surges. Phys. Today 61, 33.
% Woodruff et al., 2013. Coastal flooding by tropical cyclones and sea-level rise. Nature. 44-53.