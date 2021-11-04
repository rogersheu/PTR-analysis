#pragma TextEncoding = "UTF-8"
#pragma rtGlobals=3		// Use modern global access method and strict wave access.



/////////
//PTR Analysis, written by Roger Sheu, finished 10/31/2021, last updated 10/31/2021
//To be used in conjunction with Tofware, by Tofwerk, for Tofwerk products (PTR-TOF-MS)
//
//For converting time series of high-resolution mass peaks to mixing ratios
//Also concatenates waves from multiple files.
//
//Prior to using this ipf, do the following in Tofware:
//
//Run the built-in nontargeted analysis workflow.
//* Define reference spectrum
//* Refine peak shape
//* Mass calibrate
//* In Misc > Corrections, apply TOF duty cycle with m/Q as 37 and include a transmission function (if applicable)
//* In Misc > Settings, make sure you have the right time zone selected.
//* Select Find Peaks (use an m/z range if applicable)
//* [Optional] Edit Peak List / Check Residuals
//* Click Browse TS > Calculate and plot time series for peak list
//
//* IMPORTANT: Go into Data > Save Waves > Save Igor Text...
//////Navigate to root if you're not already there (just go up in the folders)
//////Find HDF_fileIDs_#_# (for files with ID of # to #)
//////Open Intensity_Browser_## and filter by "." (this should return only high-res masses)
//////Select all of those, then X the filter. While holding the Ctrl button, select t_start.
//////Press Do It, enter a name for the file, then pick your save location.
//
//While you're at it, find RC code 3702 (if you used the automatic zeroing and calgas function).
//On the Tofwerk panel, UserData > /TpsScriptRegData > Press "Plot Time Series" and then right-click
//on the resulting time series to pull its location up in Data Browser.
//Save that and the t_start_buf to an Igor Text file too.
//
//Import that zeroing information in as well, if applicable.
//
//Now, you have to make a list of key m/Q values. Looking at the HR mass lists for any of the files
//should suffice.  However, there's some code here that might make that easier too.
//
//I'll leave that as an exercise for the reader.
//
//Run get_all_data(). When you're prompted for a path, pick the folder containing your data.
//It's helpful if all your Igor text files are in one folder.
//
//Optional: Decomment the extract_mass_list line. This will help you get a wave containing all the
//masses in your data.


Function get_all_data()

	GetFileFolderInfo /D
	
	NewPath/O dataPath S_path
	
	String fileList = indexedfile(dataPath,-1,".itx")
	
	Variable numFiles = itemsinlist(fileList)
	
	Make/O/T/N=(numFiles) listofFileNames
	Make/O/N=(numfiles) lengthofFile, startIndex, endIndex = 0
	
	
	
	//Make a wave for each important mass
	
	Wave keyMasses
	Wave/T keyMasses_txt
	Variable i
	
	
	for(i=0; i<numpnts(keyMasses); i+=1)
		Make/O/D/N=354422 $(keyMasses_txt[i]) = NaN
	endfor
	
	Make/O/D/N=354422 date_time = 0
	
	
	Variable j
	
	for(i=0; i<numFiles; i+=1)
		String currFileName = stringfromlist(i, fileList)
		listofFileNames[i] = currFileName
		
		String currFileCode
		//sscanf currFileName, "HRpeaks_%8f_%4f.itx", currFileCode
		currFileCode = ReplaceString("HRpeaks_", currFileName, "")
		currFileCode = ReplaceString(".itx", currFileCode,"")
	
		LoadWave/O/T/P=dataPath currFileName
		
		
		Wave t_start
		Variable dataPointCount = numpnts(t_start)
		lengthofFile[i] = dataPointCount
		
		
		endIndex[i] = startIndex[i] + dataPointCount - 1
		if(i < numFiles-1)
			startIndex[i+1] = endIndex[i] + 1
		endif
		
		
		Variable fileIndex = i
		populate_waves(fileIndex)
		
		Duplicate/O date_time, date_time_backup
				
		//extract_mass_list(currFileCode)
		
		kill_mass_waves()
	endfor


end

//////////////////
//Included in get_all_data()
/////////////////

Function populate_waves(fileIndex)
	Variable fileIndex
	Variable massTol = 500
	Wave keyMasses
	Wave/T keyMasses_txt
	Wave startIndex, endIndex
	Variable indexStart = startIndex[fileIndex]
	Variable indexEnd = endIndex[fileIndex]
		
	String currWaveList = wavelist("m/Q *", ";","")
	
	Variable index = 0
	Variable i
	do
		String currWaveName = StringFromList(index, currWaveList)
		if(strlen(currWaveName) == 0)
			break
		endif
		
		Wave sourceWave = $(currWaveName)
		
		String massWaveName = ReplaceString("m/Q ", currWaveName, "")
		Variable massNum = str2num(massWaveName)
		
		for(i=0; i<numpnts(keyMasses); i+=1)
			Variable currMassSelect = keyMasses[i]
			Variable tolWidth = currMassSelect / massTol / 2
			
			if(abs(currMassSelect - massNum) < tolWidth)
				Wave wavetoAddto = $(keyMasses_txt[i])
				
				wavetoAddto[indexStart, indexEnd] = sourceWave[p-indexStart]
				//Need to do this for t_start too
				break
			endif
	
		endfor
		
		index += 1
	while(1)
	
	Wave date_time
	Wave t_start
	
	date_time[indexStart,indexEnd] = t_start[p-indexStart]


end




Function kill_mass_waves()
	String currWaveList = wavelist("m/Q *", ";","")

	Variable index
	do
		String currMass = StringFromList(index, currWaveList)
		if(strlen(currMass) == 0)
			break
		endif
		
		KillWaves/Z $(currMass)

	
		index+=1
	while(1)


end


//////////////////
//////////////////


////////////////////////////////////////////////
//Determining zeros and turning signal data into concentrations
////////////////////////////////////////////////




Function determine_zero_indices()
	Wave t_start_buf
	Wave ZeroValve_buf
	
	Variable index
	
	Make/O/D/N=0 zeroStartTime, zeroEndTime, zeroStartIndex, zeroEndIndex
	
	Variable i
	
	Redimension/N=1 zeroStartTime
	zeroStartTime[0] = t_start_buf[0]
	
	Redimension/N=1 zeroStartIndex
	zeroStartIndex[0] = 0
	Variable currIndex = 1
	Variable startorend = 0
	
	Variable prevZeroState = 0
	Variable currZeroState = ZeroValve_buf[0]
	
	for(i=1; i<numpnts(ZeroValve_buf); i+=1)
		prevZeroState = ZeroValve_buf[i-1]
		currZeroState = ZeroValve_buf[i]
		if(currZeroState != prevZeroState)
			if(startorend == 0)
				Redimension/N=(currIndex) zeroEndTime, zeroEndIndex
				zeroEndTime[currIndex-1] = t_start_buf[i]
				zeroEndIndex[currIndex-1] = i
				currIndex += 1
			endif
			if(startorend == 1)
				Redimension/N=(currIndex) zeroStartTime, zeroStartIndex
				zeroStartTime[currIndex-1] = t_start_buf[i]
				zeroStartIndex[currIndex-1] = i
			endif
			startorend = 1 - startorend
		endif
	endfor
	
	
	
	generate_zeroFlag()
end

Function generate_zeroFlag()
	Wave date_time
	Wave zeroStartTime, zeroEndTime, zeroLength
	
	Make/O/N=(numpnts(date_time)) zeroFlag, calFlag = 0
	
	Variable i,j
	for(i=0; i<numpnts(date_time); i+=1)
		Variable currTime = date_time[i]
		for(j=0; j<numpnts(zeroStartTime); j+=1)
			Variable startTime = zeroStartTime[j]
			Variable endTime = zeroEndtime[j]
			
			if(currTime >= startTime && currTime <= endTime)
					zeroFlag[i] = 1
				if(zeroLength[j] > 25)
					calFlag[i] = 1
				endif
			endif
		endfor
	endfor

end


Function remove_calsandzeros()

	String wavelistStr = wavelist("ts_*_*", ";","")
	
	wavelistStr = wavelistStr + "date_time;"
	
	Wave zeroFlag, calFlag
	
	Wave/T keyMasses_txt
	
	Make/O/N=(numpnts(keyMasses_txt)) dataZeros = 0
	
	Variable index = 0
	
	do
		String aWaveName = stringfromlist(index, wavelistStr)
		if(strlen(aWaveName) == 0)
			break
		endif
		
		Wave currWave = $(aWaveName)
		
		Variable i
		
		Duplicate/O currWave, tempWave
		
		if(index < numpnts(keyMasses_txt))
			for(i=0; i<numpnts(currWave); i+=1)
				if(zeroFlag[i] == 0 || calFlag[i] == 1)
					tempWave[i] = NaN
				endif
			endfor		
			
			WaveTransform ZapNaNs tempWave
			dataZeros[index] = mean(tempWave)
		endif
		
		for(i=0; i<numpnts(currWave); i+=1)
			if(zeroFlag[i] == 1)
				if(i > 2 && i < numpnts(currWave) - 3)
					currWave[i-3,i+3] = NaN
				endif
			endif
		endfor
		WaveTransform ZapNaNs currWave
		index += 1
	while(1)

end



//
//Function calculate_signalatzero()
//	
//	String wavelistStr = wavelist("ts_*_*", ";","")
//	
//	Wave/T keyMasses_txt
//	
//	Make/O/N=(numpnts(keyMasses_txt)) dataLengths = 0
//	
//	Variable index
//	
//	do
//		String aWaveName = stringfromlist(index, wavelistStr)
//		if(strlen(aWaveName) == 0)
//			break
//		endif
//		
//		Wave currWave = $(aWaveName)
//		
//		dataLengths = numpnts($(keyMasses_txt))
//
//		index += 1
//
//	while(1)
//
//end	



Function ts_lengths()
	
	String wavelistStr = wavelist("ts_*_*", ";","")
	
	Wave/T keyMasses_txt
	
	Make/O/N=(numpnts(keyMasses_txt)) dataLengths = 0
	
	Variable index
	
	do
		String aWaveName = stringfromlist(index, wavelistStr)
		if(strlen(aWaveName) == 0)
			break
		endif
		
		Wave currWave = $(aWaveName)
		
		dataLengths = numpnts($(keyMasses_txt))

		index += 1

	while(1)

end	


////////////////////////////////////////////////
////////////////////////////////////////////////



Function calcconcs()
	Wave/t keyMasses_txt
	
	Wave dataZeros, Sens
	
	Variable i
	
	for(i=0; i<numpnts(keyMasses_txt); i+=1)
		
		String ppbWaveName = "ppb_" + keyMasses_txt[i]
		
		Duplicate/O $(keyMasses_txt[i]), $(ppbWaveName)
		
		Wave newppbWave = $(ppbWaveName)
		
		newppbWave -= dataZeros[i]
		newppbWave /= Sens[i]
	
	endfor
end






//////////////////////////////////////////////
//Getting a mass list



Function extract_mass_list(fileCode)

	String fileCode
	String currWaveList = wavelist("m/Q *", ";","")

	String massListStr = "massestxt_" + fileCode
	Make/O/T/N=(itemsinlist(currWaveList)) $(massListStr) = ""
	Wave/T currMassList = $(massListStr)

	Variable index
	do
		String currMass = StringFromList(index, currWaveList)
		if(strlen(currMass) == 0)
			break
		endif
		
		currMassList[index] = currMass

	
		index+=1
	while(1)
		
	Duplicate/O/T currMassList, tempMassList
	tempMassList = ReplaceString("m/Q ", tempMassList, "")

	
	String massNums = "masses_" + fileCode
	Make/O/D/N=(numpnts(currMassList)) $(massNums)
	Wave masses = $(massNums)
	
	
	Variable i	
	for(i=0; i<numpnts(currMassList); i+=1)
//		String truncNumber_txt
//		String decimal_txt
		Variable truncNum
		Variable decimal
		
//		Variable tempMass = str2num(tempMassList[i])
//		truncNum = floor(tempMass)
//		decimal = tempMass - truncNum
//		
//		decimal *= 100
//		decimal = round(decimal)
//		decimal /= 100
//		
//		masses = trunc(str2num(tempMassList)*100)/100
		

		sscanf tempMassList[i], "%d.%4d", truncNum, decimal

		masses[i] = truncNum + decimal/10000
	endfor
	
	Sort masses, masses, currMassList

end




Function single_mass_list()

	String currWaveList = wavelist("m/Q *", ";","")

	Make/O/T/N=(itemsinlist(currWaveList)) masses_txt = ""

	Variable index
	do
		String currMass = StringFromList(index, currWaveList)
		if(strlen(currMass) == 0)
			break
		endif
		
		masses_txt[index] = currMass

	
		index+=1
	while(1)
		
	Duplicate/O/T masses_txt, tempMass_txt
	tempMass_txt = ReplaceString("m/Q ", tempMass_txt, "")
	
	Variable i
	Make/O/N=(numpnts(masses_txt)) masses
	
	for(i=0; i<numpnts(masses_txt); i+=1)
		String truncNumber_txt
		String decimal_txt
		
		sscanf masses_txt[i], "%d.%4d", truncNumber_txt, decimal_txt //Rounding issues with floats
		
		String newNumber = truncNumber_txt + "." + decimal_txt
		
		masses[i] = str2num(newNumber)
	endfor

end








Function concat_masses()
	
	KillWaves/Z all_masses
	
	Make/O/N=0 all_masses
	String massStr = wavelist("masses_*", ";", "")
	Concatenate/O/NP massStr, all_masses

	Sort all_masses, all_masses
	
	Duplicate/O all_masses, OGmasslist

	combine_masses()

end



Function combine_masses()
	Wave all_masses

	Variable massTol = 500
	
	Variable i,j
	
	for(i=0; i<numpnts(all_masses); i+=1)
		Variable currMass = all_masses[i]
		Variable massHigh = currMass + currMass / massTol
		if(abs(currMass - floor(currMass)) < 0.25)
			Make/O/N=0 tempWave
			Variable index = 0
			for(j=i+1; j<numpnts(all_masses); j+=1)
				Variable comparedMass = all_masses[j]
				if (massHigh > comparedMass)
					Redimension/N=(index+1) tempWave
					tempWave[index] = comparedMass
					index += 1
					
					DeletePoints j, 1, all_masses
					j -= 1
				else
					break
				endif			
			endfor
			if(numpnts(tempWave) > 0)
				all_masses[i] = mean(tempWave)
			endif
		else
			DeletePoints i, 1, all_masses
			i -= 1
		endif
	endfor
end


/////////////////////////////////////





Function scrub(startIndex, endIndex)
	Variable startIndex, endIndex

	String wavelistStr = wavelist("ppb_ts_*", ";","")
	
	wavelistStr = wavelistStr + "date_time;"
	
	
	Variable index
	
	do
		String aWaveName = stringfromlist(index, wavelistStr)
		if(strlen(aWaveName) == 0)
			break
		endif
		
		Wave currWave = $(aWaveName)
		
		currWave[startIndex, endIndex] = NaN
		
		
		WaveTransform ZapNaNs currWave
		index += 1

	while(1)
	

end

///2768, 2794
///62842, 62917
///193626, 193633
///62811, 63191