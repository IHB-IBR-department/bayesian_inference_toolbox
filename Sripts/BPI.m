%% ========================================================================
% Bayesian parameter inference (Friston & Penny, 2003; Penny & Ridgway, 2013)
% The "ROPE-only" and "HDI+ROPE" decision rules (Kruschke, 2018)

% Masharipov Ruslan, May, 2021
% Institute of Human Brain of RAS, St. Petersburg, Russia
% Neuroimaging lab
% masharipov@ihb.spb.ru
% =========================================================================

% Before running the script use SPM12 (v6906) to:
% 1) Create GLM for one sample test or two sample test
% 2) Estimate model using method: Classical
% 3) Estimate model using method: Bayesian 2nd-level
%% ========================================================================
clear
close all
tic
% Load SPM.mat
[spmmatfile] = spm_select(1,'^SPM\.mat$','Select SPM.mat');
load(spmmatfile);
% Set path
path = SPM.swd;
cd(path)

% One or two sample
switch char(SPM.xX.name(1))
    case 'mean'
        c = spm_input('Select contrast:','+1','+1|-1',[1,-1],1);
    case 'Group_{1}'
        c1 = [1;-1]; c2 = [-1;1];
        c = spm_input('Select contrast:','+1','[1 -1]|[-1 1]',[c1,c2],1);
        c = c';
    otherwise
    error('Error: Choose GLM for One smaple or Two sample test')
end
    

% Classical voxel-wise pFWE<0.05
XYZ  = SPM.xVol.XYZ;
switch char(SPM.xX.name(1))
    case 'mean'
        class_B = spm_data_read(SPM.Vbeta,'xyz',XYZ);
        class_B = c*class_B;
    case 'Group_{1}'
        class_B1 = spm_data_read(SPM.Vbeta(1),'xyz',XYZ);
        class_B2 = spm_data_read(SPM.Vbeta(2),'xyz',XYZ);
        class_B = c'*[class_B1;class_B2];   
end
class_l   = spm_data_read(SPM.VResMS,'xyz',XYZ);    % get hyperparamters
class_Vc  = c'*SPM.xX.Bcov*c;
SE  = sqrt(class_l*class_Vc);       % and standard error
Z   = class_B./SE;
df = [1 SPM.xX.erdf];
S    = SPM.xVol.S;                  %-search Volume {voxels}
R    = SPM.xVol.R;                  %-search Volume {resels}
u = spm_uc(0.05,df,'T',R,1,S);
FWE_pos_eff = sum(Z>=u);

% Read Posterior Beta
switch char(SPM.xX.name(1))
    case 'mean'
        cB = spm_data_read(SPM.VCbeta,'xyz',XYZ);
        cB = c*cB;
    case 'Group_{1}'
        cB1 = spm_data_read(SPM.VCbeta(1),'xyz',XYZ);
        cB2 = spm_data_read(SPM.VCbeta(2),'xyz',XYZ);
        cB = c'*[cB1;cB2];   
end

% Compute Posterior Variance
VcB   = c'*SPM.PPM.Cby*c;
for j = 1:length(SPM.PPM.l)
    l   = spm_data_read(SPM.VHp(j),'xyz',XYZ);              % hyperparameter
    VcB = VcB + (c'*SPM.PPM.dC{j}*c)*(l - SPM.PPM.l(j));    % Taylor approximation
end

% Decision rule
rule = spm_input('Decision rule:','+1','ROPE-only|HDI+ROPE',[1,2],1);

% Effect size threshold based on maximum overlap with classic pFWE<0.05
DiceMax = 2;
if FWE_pos_eff>0
    DiceMax = spm_input('ES threshold based on DiceMax:','+1','Yes|No',[1,2],2);    
end

% Effect size threshold
fprintf('===============================\n');
prior_SD = full(sqrt(c'*SPM.PPM.Cb*c));
if DiceMax == 1
    ES = [0:prior_SD/100:prior_SD*10];
    FWE_pos_eff_bin = (Z>=u);
    f = waitbar(0,'Computing y(DiceMax) threshold');
    HDImax = spm_invNcdf(0.975,cB,VcB);
    HDImin = spm_invNcdf(0.025,cB,VcB);
    for thr = 1:length(ES)
        if rule == 1 % ROPE-only
            ROPE_only_pos_eff = log((normcdf(-ES(thr),-cB,sqrt(VcB)))./normcdf(ES(thr),cB,sqrt(VcB)));
            Dice(thr) = 2.*sum((ROPE_only_pos_eff>=3).*FWE_pos_eff_bin)./(sum((ROPE_only_pos_eff>=3))+sum(FWE_pos_eff_bin));
            waitbar(thr/length(ES),f,'Computing y(DiceMax) threshold')
        else
            HDI_ROPE_pos_eff = (HDImin>ES(thr));
            Dice(thr) = 2.*sum(HDI_ROPE_pos_eff.*FWE_pos_eff_bin)./(sum(HDI_ROPE_pos_eff)+sum(FWE_pos_eff_bin));
            waitbar(thr/length(ES),f,'Computing y(DiceMax) threshold')
        end
    end
    delete(f)
    [DiceMax, I] = max(Dice);
    ES = ES(I);
    fprintf(['ES threshold based on DiceMax:\n' 'DiceMax = ' num2str(DiceMax) '\n' 'y(DiceMax) threshold = ' num2str(ES) '\n'])
%     f = msgbox({'ES threshold based on DiceMax:'; ['DiceMax = ' num2str(DiceMax)]; ['y(DiceMax) threshold = ' num2str(ES)]});
%     th = findall(f, 'Type', 'Text');
%     th.FontSize = 14;
%     deltaWidth = sum(th.Extent([1,3]))-f.Position(3) + th.Extent(1);
%     deltaHeight = sum(th.Extent([2,4]))-f.Position(4) + 10;
%     f.Position([3,4]) = f.Position([3,4]) + [deltaWidth, deltaHeight]; f.Resize = 'on';
else
    ES = spm_input('ES threshold:','+1','e',prior_SD,[1,1]); % The default is one conditional s.d. of the contrast
end

%Posterior probability (PP)
post_pos = (normcdf(-ES,-cB,sqrt(VcB)));
post_neg = (normcdf(-ES,cB,sqrt(VcB)));
post_null = (normcdf(ES,cB,sqrt(VcB)) - normcdf(-ES,cB,sqrt(VcB)));

%Log Posterior Odds (LPO)
LPO_pos = log((normcdf(-ES,-cB,sqrt(VcB)))./normcdf(ES,cB,sqrt(VcB)));
LPO_neg = log((normcdf(-ES,cB,sqrt(VcB)))./(1 - normcdf(-ES,cB,sqrt(VcB))));
LPO_null = log((normcdf(ES,cB,sqrt(VcB)) - normcdf(-ES,cB,sqrt(VcB)))./(1 - normcdf(ES,cB,sqrt(VcB)) + normcdf(-ES,cB,sqrt(VcB))));

%% ========================================================================
% Save images 
switch rule
    case 1 %ROPE only
        status = exist('ROPE_only');
        if status ~= 7
            mkdir 'ROPE_only'; 
        end
        rule_dir = 'ROPE_only';
        
        post_all = [post_pos; post_null; post_neg];
        LPO_all = [LPO_pos; LPO_null; LPO_neg];
        
    case 2 %HDI+ROPE
        status = exist('HDI_ROPE');
        if status ~= 7
            mkdir 'HDI_ROPE'; 
        end
        rule_dir = 'HDI_ROPE';
        
        HDImax = spm_invNcdf(0.975,cB,VcB);
        HDImin = spm_invNcdf(0.025,cB,VcB);
        ROPE_max = ES;
        ROPE_min = -ES;

        HDI_ROPE_PP_pos_eff = NaN(1,length(cB)); HDI_ROPE_LPO_pos_eff = NaN(1,length(cB));
        HDI_ROPE_PP_neg_eff = NaN(1,length(cB)); HDI_ROPE_LPO_neg_eff = NaN(1,length(cB));
        HDI_ROPE_PP_null_eff = NaN(1,length(cB)); HDI_ROPE_LPO_null_eff = NaN(1,length(cB));
        
        HDI_ROPE_PP_pos_eff(HDImin>ROPE_max) = post_pos(HDImin>ROPE_max);
        HDI_ROPE_PP_neg_eff(HDImax<ROPE_min) = post_neg(HDImax<ROPE_min);        
        HDI_ROPE_PP_null_eff(HDImin>=ROPE_min & HDImax<=ROPE_max) = post_null(HDImin>=ROPE_min & HDImax<=ROPE_max);

        HDI_ROPE_LPO_pos_eff(HDImin>ROPE_max) = LPO_pos(HDImin>ROPE_max);
        HDI_ROPE_LPO_neg_eff(HDImax<ROPE_min) = LPO_neg(HDImax<ROPE_min);        
        HDI_ROPE_LPO_null_eff(HDImin>=ROPE_min & HDImax<=ROPE_max) = LPO_null(HDImin>=ROPE_min & HDImax<=ROPE_max);
        
        post_all = [HDI_ROPE_PP_pos_eff; HDI_ROPE_PP_null_eff; HDI_ROPE_PP_neg_eff];
        LPO_all = [HDI_ROPE_LPO_pos_eff; HDI_ROPE_LPO_null_eff; HDI_ROPE_LPO_neg_eff];
end

%name, description, values
name_1 = {strrep(['_01_Positive_effect_[' num2str(ES) '_PSC]'],'.',',')};
name_2 = {strrep(['_02_Null_effect_[' num2str(ES) '_PSC]'],'.',',')};
name_3 = {strrep(['_03_Negative_effect_[' num2str(ES) '_PSC]'],'.',',')};
descr_1 = {['ES threshold = ' num2str(ES) ' PSC']};    
descr_2 = {['ES threshold = ' num2str(ES) ' PSC']};
descr_3 = {['ES threshold = ' num2str(ES) ' PSC']};

info = struct('name', [name_1 name_2 name_3],...
             'description', [descr_1 descr_2 descr_3]);

%hdr
hdr = spm_vol([path '\Cbeta_0001.nii']);

%mask
mask = spm_read_vols(hdr);
mask(~isnan(mask)) = 0;

%iXYZ
iXYZ = cumprod([1,SPM.xVol.DIM(1:2)'])*XYZ - sum(cumprod(SPM.xVol.DIM(1:2)'));

%save PostProb
for j=1:3
        hdr.fname = [path '\' rule_dir '\PPM' info(j).name '.nii'];
        hdr.descrip = [info(j).description];    
        hdr.private.descrip = [info(j).description];
        tmp           = mask;
        tmp(iXYZ)     = post_all(j,:);
        spm_write_vol(hdr,tmp);
        clear tmp 
end
    
%save LPO
for j=1:3
        hdr.fname = [path '\' rule_dir '\LPO' info(j).name '.nii'];
        hdr.descrip = [info(j).description];    
        hdr.private.descrip = [info(j).description];
        tmp           = mask;
        tmp(iXYZ)     = LPO_all(j,:);
        spm_write_vol(hdr,tmp);
        clear tmp         
end

time = toc;
fprintf(['Done in ' num2str(time) ' s\n'])
fprintf('===============================\n');

clear
close all

% LPO_pos = [path '\' rule_dir '\LPO' info(1).name '.nii'];
% LPO_null = [path '\' rule_dir '\LPO' info(2).name '.nii'];
% LPO_neg = [path '\' rule_dir '\LPO' info(3).name '.nii'];
% Bin_Mask = [path '\mask.nii'];



