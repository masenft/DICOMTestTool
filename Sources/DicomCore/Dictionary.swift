import Foundation

public extension Tag {
    // Command
    static let commandGroupLength = Tag(0x0000, 0x0000)
    static let affectedSOPClassUID = Tag(0x0000, 0x0002)
    static let commandField = Tag(0x0000, 0x0100)
    static let messageID = Tag(0x0000, 0x0110)
    static let messageIDBeingRespondedTo = Tag(0x0000, 0x0120)
    static let moveDestination = Tag(0x0000, 0x0600)
    static let priority = Tag(0x0000, 0x0700)
    static let commandDataSetType = Tag(0x0000, 0x0800)
    static let status = Tag(0x0000, 0x0900)
    static let errorComment = Tag(0x0000, 0x0902)
    static let affectedSOPInstanceUID = Tag(0x0000, 0x1000)
    static let remainingSubops = Tag(0x0000, 0x1020)
    static let completedSubops = Tag(0x0000, 0x1021)
    static let failedSubops = Tag(0x0000, 0x1022)
    static let warningSubops = Tag(0x0000, 0x1023)
    // Meta
    static let fileMetaInformationVersion = Tag(0x0002, 0x0001)
    static let mediaStorageSOPClassUID = Tag(0x0002, 0x0002)
    static let mediaStorageSOPInstanceUID = Tag(0x0002, 0x0003)
    static let transferSyntaxUID = Tag(0x0002, 0x0010)
    static let implementationClassUID = Tag(0x0002, 0x0012)
    static let implementationVersionName = Tag(0x0002, 0x0013)
    static let sourceApplicationEntityTitle = Tag(0x0002, 0x0016)
    // Dataset
    static let specificCharacterSet = Tag(0x0008, 0x0005)
    static let imageType = Tag(0x0008, 0x0008)
    static let sopClassUID = Tag(0x0008, 0x0016)
    static let sopInstanceUID = Tag(0x0008, 0x0018)
    static let studyDate = Tag(0x0008, 0x0020)
    static let seriesDate = Tag(0x0008, 0x0021)
    static let contentDate = Tag(0x0008, 0x0023)
    static let studyTime = Tag(0x0008, 0x0030)
    static let seriesTime = Tag(0x0008, 0x0031)
    static let contentTime = Tag(0x0008, 0x0033)
    static let accessionNumber = Tag(0x0008, 0x0050)
    static let queryRetrieveLevel = Tag(0x0008, 0x0052)
    static let modality = Tag(0x0008, 0x0060)
    static let modalitiesInStudy = Tag(0x0008, 0x0061)
    static let conversionType = Tag(0x0008, 0x0064)
    static let manufacturer = Tag(0x0008, 0x0070)
    static let institutionName = Tag(0x0008, 0x0080)
    static let referringPhysicianName = Tag(0x0008, 0x0090)
    static let stationName = Tag(0x0008, 0x1010)
    static let studyDescription = Tag(0x0008, 0x1030)
    static let seriesDescription = Tag(0x0008, 0x103E)
    static let patientName = Tag(0x0010, 0x0010)
    static let patientID = Tag(0x0010, 0x0020)
    static let patientBirthDate = Tag(0x0010, 0x0030)
    static let patientSex = Tag(0x0010, 0x0040)
    static let studyInstanceUID = Tag(0x0020, 0x000D)
    static let seriesInstanceUID = Tag(0x0020, 0x000E)
    static let studyID = Tag(0x0020, 0x0010)
    static let seriesNumber = Tag(0x0020, 0x0011)
    static let instanceNumber = Tag(0x0020, 0x0013)
    static let numberOfPatientRelatedStudies = Tag(0x0020, 0x1200)
    static let numberOfStudyRelatedSeries = Tag(0x0020, 0x1206)
    static let numberOfStudyRelatedInstances = Tag(0x0020, 0x1208)
    static let numberOfSeriesRelatedInstances = Tag(0x0020, 0x1209)
    static let samplesPerPixel = Tag(0x0028, 0x0002)
    static let photometricInterpretation = Tag(0x0028, 0x0004)
    static let planarConfiguration = Tag(0x0028, 0x0006)
    static let numberOfFrames = Tag(0x0028, 0x0008)
    static let rows = Tag(0x0028, 0x0010)
    static let columns = Tag(0x0028, 0x0011)
    static let bitsAllocated = Tag(0x0028, 0x0100)
    static let bitsStored = Tag(0x0028, 0x0101)
    static let highBit = Tag(0x0028, 0x0102)
    static let pixelRepresentation = Tag(0x0028, 0x0103)
    static let windowCenter = Tag(0x0028, 0x1050)
    static let windowWidth = Tag(0x0028, 0x1051)
    static let rescaleIntercept = Tag(0x0028, 0x1052)
    static let rescaleSlope = Tag(0x0028, 0x1053)
    static let requestedProcedureDescription = Tag(0x0032, 0x1060)
    static let scheduledStationAETitle = Tag(0x0040, 0x0001)
    static let scheduledProcedureStepStartDate = Tag(0x0040, 0x0002)
    static let scheduledProcedureStepStartTime = Tag(0x0040, 0x0003)
    static let scheduledPerformingPhysicianName = Tag(0x0040, 0x0006)
    static let scheduledProcedureStepDescription = Tag(0x0040, 0x0007)
    static let scheduledProcedureStepID = Tag(0x0040, 0x0009)
    static let scheduledStationName = Tag(0x0040, 0x0010)
    static let scheduledProcedureStepStatus = Tag(0x0040, 0x0020)
    static let scheduledProcedureStepSequence = Tag(0x0040, 0x0100)
    static let requestedProcedureID = Tag(0x0040, 0x1001)
    static let pixelData = Tag(0x7FE0, 0x0010)
    static let item = Tag(0xFFFE, 0xE000)
    static let itemDelimitation = Tag(0xFFFE, 0xE00D)
    static let sequenceDelimitation = Tag(0xFFFE, 0xE0DD)
}

public enum DicomDictionary {
    private static let table: [UInt32: (VR, String)] = {
        var t: [UInt32: (VR, String)] = [:]
        for line in raw.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 2)
            guard parts.count == 3, let tag = UInt32(parts[0], radix: 16), let vr = VR(rawValue: String(parts[1])) else { continue }
            t[tag] = (vr, String(parts[2]))
        }
        return t
    }()

    public static func vr(for tag: Tag) -> VR {
        if let e = table[tag.raw] { return e.0 }
        if tag.element == 0x0000 { return .UL }
        if tag.isPrivate && tag.element >= 0x0010 && tag.element <= 0x00FF { return .LO } // private creator
        return .UN
    }

    public static func name(for tag: Tag) -> String {
        if let e = table[tag.raw] { return e.1 }
        if tag.element == 0x0000 { return "GroupLength" }
        if tag.isPrivate { return (tag.element >= 0x0010 && tag.element <= 0x00FF) ? "PrivateCreator" : "Private Tag" }
        return "Unbekannt"
    }

    private static let raw = """
    00000000 UL CommandGroupLength
    00000002 UI AffectedSOPClassUID
    00000003 UI RequestedSOPClassUID
    00000100 US CommandField
    00000110 US MessageID
    00000120 US MessageIDBeingRespondedTo
    00000600 AE MoveDestination
    00000700 US Priority
    00000800 US CommandDataSetType
    00000900 US Status
    00000901 AT OffendingElement
    00000902 LO ErrorComment
    00000903 US ErrorID
    00001000 UI AffectedSOPInstanceUID
    00001001 UI RequestedSOPInstanceUID
    00001002 US EventTypeID
    00001005 AT AttributeIdentifierList
    00001008 US ActionTypeID
    00001020 US NumberOfRemainingSuboperations
    00001021 US NumberOfCompletedSuboperations
    00001022 US NumberOfFailedSuboperations
    00001023 US NumberOfWarningSuboperations
    00001030 AE MoveOriginatorApplicationEntityTitle
    00001031 US MoveOriginatorMessageID
    00020000 UL FileMetaInformationGroupLength
    00020001 OB FileMetaInformationVersion
    00020002 UI MediaStorageSOPClassUID
    00020003 UI MediaStorageSOPInstanceUID
    00020010 UI TransferSyntaxUID
    00020012 UI ImplementationClassUID
    00020013 SH ImplementationVersionName
    00020016 AE SourceApplicationEntityTitle
    00020100 UI PrivateInformationCreatorUID
    00020102 OB PrivateInformation
    00041130 CS FileSetID
    00041200 UL OffsetOfTheFirstDirectoryRecordOfTheRootDirectoryEntity
    00041202 UL OffsetOfTheLastDirectoryRecordOfTheRootDirectoryEntity
    00041212 US FileSetConsistencyFlag
    00041220 SQ DirectoryRecordSequence
    00041400 UL OffsetOfTheNextDirectoryRecord
    00041410 US RecordInUseFlag
    00041420 UL OffsetOfReferencedLowerLevelDirectoryEntity
    00041430 CS DirectoryRecordType
    00041500 CS ReferencedFileID
    00041510 UI ReferencedSOPClassUIDInFile
    00041511 UI ReferencedSOPInstanceUIDInFile
    00041512 UI ReferencedTransferSyntaxUIDInFile
    00080005 CS SpecificCharacterSet
    00080008 CS ImageType
    00080012 DA InstanceCreationDate
    00080013 TM InstanceCreationTime
    00080014 UI InstanceCreatorUID
    00080016 UI SOPClassUID
    00080018 UI SOPInstanceUID
    00080020 DA StudyDate
    00080021 DA SeriesDate
    00080022 DA AcquisitionDate
    00080023 DA ContentDate
    0008002A DT AcquisitionDateTime
    00080030 TM StudyTime
    00080031 TM SeriesTime
    00080032 TM AcquisitionTime
    00080033 TM ContentTime
    00080050 SH AccessionNumber
    00080052 CS QueryRetrieveLevel
    00080054 AE RetrieveAETitle
    00080056 CS InstanceAvailability
    00080060 CS Modality
    00080061 CS ModalitiesInStudy
    00080062 UI SOPClassesInStudy
    00080064 CS ConversionType
    00080068 CS PresentationIntentType
    00080070 LO Manufacturer
    00080080 LO InstitutionName
    00080081 ST InstitutionAddress
    00080090 PN ReferringPhysicianName
    00080100 SH CodeValue
    00080102 SH CodingSchemeDesignator
    00080103 SH CodingSchemeVersion
    00080104 LO CodeMeaning
    00080201 SH TimezoneOffsetFromUTC
    00081010 SH StationName
    00081030 LO StudyDescription
    00081032 SQ ProcedureCodeSequence
    0008103E LO SeriesDescription
    00081040 LO InstitutionalDepartmentName
    00081048 PN PhysiciansOfRecord
    00081050 PN PerformingPhysicianName
    00081060 PN NameOfPhysiciansReadingStudy
    00081070 PN OperatorsName
    00081080 LO AdmittingDiagnosesDescription
    00081090 LO ManufacturerModelName
    00081110 SQ ReferencedStudySequence
    00081111 SQ ReferencedPerformedProcedureStepSequence
    00081115 SQ ReferencedSeriesSequence
    00081120 SQ ReferencedPatientSequence
    00081140 SQ ReferencedImageSequence
    00081150 UI ReferencedSOPClassUID
    00081155 UI ReferencedSOPInstanceUID
    00081160 IS ReferencedFrameNumber
    00082111 ST DerivationDescription
    00082112 SQ SourceImageSequence
    00082218 SQ AnatomicRegionSequence
    00100010 PN PatientName
    00100020 LO PatientID
    00100021 LO IssuerOfPatientID
    00100030 DA PatientBirthDate
    00100032 TM PatientBirthTime
    00100040 CS PatientSex
    00101000 LO OtherPatientIDs
    00101001 PN OtherPatientNames
    00101010 AS PatientAge
    00101020 DS PatientSize
    00101030 DS PatientWeight
    00101040 LO PatientAddress
    00102000 LO MedicalAlerts
    00102110 LO Allergies
    00102154 SH PatientTelephoneNumbers
    00102160 SH EthnicGroup
    001021B0 LT AdditionalPatientHistory
    001021C0 US PregnancyStatus
    00104000 LT PatientComments
    00180010 LO ContrastBolusAgent
    00180015 CS BodyPartExamined
    00180020 CS ScanningSequence
    00180050 DS SliceThickness
    00180060 DS KVP
    00180080 DS RepetitionTime
    00180081 DS EchoTime
    00180087 DS MagneticFieldStrength
    00180088 DS SpacingBetweenSlices
    00181000 LO DeviceSerialNumber
    00181020 LO SoftwareVersions
    00181030 LO ProtocolName
    00181110 DS DistanceSourceToDetector
    00181111 DS DistanceSourceToPatient
    00181150 IS ExposureTime
    00181151 IS XRayTubeCurrent
    00181152 IS Exposure
    00181164 DS ImagerPixelSpacing
    00181210 SH ConvolutionKernel
    00185100 CS PatientPosition
    00185101 CS ViewPosition
    0020000D UI StudyInstanceUID
    0020000E UI SeriesInstanceUID
    00200010 SH StudyID
    00200011 IS SeriesNumber
    00200012 IS AcquisitionNumber
    00200013 IS InstanceNumber
    00200020 CS PatientOrientation
    00200032 DS ImagePositionPatient
    00200037 DS ImageOrientationPatient
    00200052 UI FrameOfReferenceUID
    00200060 CS Laterality
    00200062 CS ImageLaterality
    00201002 IS ImagesInAcquisition
    00201040 LO PositionReferenceIndicator
    00201041 DS SliceLocation
    00201200 IS NumberOfPatientRelatedStudies
    00201202 IS NumberOfPatientRelatedSeries
    00201204 IS NumberOfPatientRelatedInstances
    00201206 IS NumberOfStudyRelatedSeries
    00201208 IS NumberOfStudyRelatedInstances
    00201209 IS NumberOfSeriesRelatedInstances
    00204000 LT ImageComments
    00280002 US SamplesPerPixel
    00280004 CS PhotometricInterpretation
    00280006 US PlanarConfiguration
    00280008 IS NumberOfFrames
    00280009 AT FrameIncrementPointer
    00280010 US Rows
    00280011 US Columns
    00280030 DS PixelSpacing
    00280034 IS PixelAspectRatio
    00280100 US BitsAllocated
    00280101 US BitsStored
    00280102 US HighBit
    00280103 US PixelRepresentation
    00280106 US SmallestImagePixelValue
    00280107 US LargestImagePixelValue
    00280301 CS BurnedInAnnotation
    00281040 CS PixelIntensityRelationship
    00281050 DS WindowCenter
    00281051 DS WindowWidth
    00281052 DS RescaleIntercept
    00281053 DS RescaleSlope
    00281054 LO RescaleType
    00281055 LO WindowCenterWidthExplanation
    00282110 CS LossyImageCompression
    00282112 DS LossyImageCompressionRatio
    00282114 CS LossyImageCompressionMethod
    00321032 PN RequestingPhysician
    00321033 LO RequestingService
    00321060 LO RequestedProcedureDescription
    00321064 SQ RequestedProcedureCodeSequence
    00380010 LO AdmissionID
    00380050 LO SpecialNeeds
    00380300 LO CurrentPatientLocation
    00380500 LO PatientState
    00400001 AE ScheduledStationAETitle
    00400002 DA ScheduledProcedureStepStartDate
    00400003 TM ScheduledProcedureStepStartTime
    00400004 DA ScheduledProcedureStepEndDate
    00400005 TM ScheduledProcedureStepEndTime
    00400006 PN ScheduledPerformingPhysicianName
    00400007 LO ScheduledProcedureStepDescription
    00400008 SQ ScheduledProtocolCodeSequence
    00400009 SH ScheduledProcedureStepID
    00400010 SH ScheduledStationName
    00400011 SH ScheduledProcedureStepLocation
    00400012 LO PreMedication
    00400020 CS ScheduledProcedureStepStatus
    00400100 SQ ScheduledProcedureStepSequence
    00400241 AE PerformedStationAETitle
    00400244 DA PerformedProcedureStepStartDate
    00400245 TM PerformedProcedureStepStartTime
    00400253 SH PerformedProcedureStepID
    00400254 LO PerformedProcedureStepDescription
    00400275 SQ RequestAttributesSequence
    00401001 SH RequestedProcedureID
    00401002 LO ReasonForTheRequestedProcedure
    00401003 SH RequestedProcedurePriority
    00401004 LO PatientTransportArrangements
    00401400 LT RequestedProcedureComments
    00402016 LO PlacerOrderNumberImagingServiceRequest
    00402017 LO FillerOrderNumberImagingServiceRequest
    00402400 LT ImagingServiceRequestComments
    0040A010 CS RelationshipType
    0040A040 CS ValueType
    0040A043 SQ ConceptNameCodeSequence
    0040A160 UT TextValue
    0040A168 SQ ConceptCodeSequence
    0040A730 SQ ContentSequence
    00420010 ST DocumentTitle
    00420011 OB EncapsulatedDocument
    00420012 LO MIMETypeOfEncapsulatedDocument
    00540081 US NumberOfSlices
    00880140 UI StorageMediaFileSetUID
    20000010 IS NumberOfCopies
    20000020 CS PrintPriority
    20000030 CS MediumType
    20000040 CS FilmDestination
    20100010 ST ImageDisplayFormat
    20100040 CS FilmOrientation
    20100050 CS FilmSizeID
    20200010 US ImageBoxPosition
    7FE00008 OF FloatPixelData
    7FE00009 OD DoubleFloatPixelData
    7FE00010 OW PixelData
    FFFEE000 UN Item
    FFFEE00D UN ItemDelimitationItem
    FFFEE0DD UN SequenceDelimitationItem
    """
}
