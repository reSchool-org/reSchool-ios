import Foundation

struct LoginPayload: Codable {
    let username: String
    let password_hash: String
    let device_payload: DevicePayload
}

struct DevicePayload: Codable {
    let cliType: String
    let cliVer: String
    let pushToken: String
    let deviceId: String
    let deviceName: String
    let deviceModel: Int
    let cliOs: String
}

struct StateResponse: Codable {
    let userId: Int?
    let profile: Profile?
    let user: UserInfo?
}

struct Profile: Codable {
    let id: Int?
    let firstName: String?
    let lastName: String?
    let middleName: String?
    let phoneMob: String?

    var fullName: String {
        let parts = [lastName, firstName, middleName].compactMap { $0 }
        return parts.joined(separator: " ")
    }
}

struct UserInfo: Codable {
    let prsId: Int?
    let username: String?
}

struct ThreadResponse: Codable {
    let threadId: Int
    let subject: String?
    let msgPreview: String?
    let senderFio: String?
    let sendDate: Double
    let imageId: Int?
    let imgObjType: String?
    let imgObjId: Int?
    let dlgType: Int?
}

struct MessageResponse: Codable, Identifiable {
    var id: Int { msgId ?? Int(createDate) }
    let msgId: Int?
    let msg: String?
    let senderFio: String?
    let createDate: Double
    let isOwner: Bool?
    let senderId: Int?
    let imageId: Int?
    let imgObjType: String?
    let imgObjId: Int?
}

struct DiaryUnitResponse: Codable {
    let result: [DiaryUnit]?
}

struct DiaryUnit: Codable, Identifiable {
    var id: String { String(unitId ?? 0) }
    let unitId: Int?
    let unitName: String?
    let overMark: Double?
    let totalMark: Double?
    let rating: String?

    enum CodingKeys: String, CodingKey {
        case unitId, unitName, overMark, totalMark, rating
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        unitId = try container.decodeIfPresent(Int.self, forKey: .unitId)
        unitName = try container.decodeIfPresent(String.self, forKey: .unitName)
        overMark = try container.decodeIfPresent(Double.self, forKey: .overMark)
        rating = try container.decodeIfPresent(String.self, forKey: .rating)

        if let val = try? container.decode(Double.self, forKey: .totalMark) {
            totalMark = val
        } else if let valStr = try? container.decode(String.self, forKey: .totalMark) {
            totalMark = Double(valStr)
        } else {
            totalMark = nil
        }
    }

    init(unitId: Int?, unitName: String?, overMark: Double?, totalMark: Double?, rating: String? = nil) {
        self.unitId = unitId
        self.unitName = unitName
        self.overMark = overMark
        self.totalMark = totalMark
        self.rating = rating
    }
}

struct GroupResponse: Codable {
    let groupId: Int?
    let groupName: String?
    let begDate: Double?
}

struct PeriodResponse: Codable {
    let id: Int?
    let name: String?
    let date1: Double?
    let date2: Double?
    let date1Str: String?
    let date2Str: String?
    let parentId: Int?
    let items: [PeriodResponse]?
    let typeCode: String?
}

struct DiaryPeriodResponse: Codable {
    let result: [DiaryPeriodLesson]?
}

struct DiaryPeriodLesson: Codable {
    let unitId: Int?
    let part: [DiaryPart]?
}

struct DiaryPart: Codable {
    let mark: [DiaryMark]?
}

struct DiaryMark: Codable {
    let markValue: String?
}

struct PrsDiaryResponse: Codable {
    let lesson: [PrsDiaryLesson]?
    let user: [PrsDiaryUser]?
}

struct PrsDiaryUser: Codable {
    let id: Int?
    let mark: [PrsDiaryMark]?
}

struct PrsDiaryMark: Codable {
    let id: Int?
    let value: String?
    let lessonID: Int?
    let partType: String?
    let partID: Int?
}

struct PrsDiaryLesson: Codable, Identifiable {
    let id: Int?
    let date: Double?
    let numInDay: Int?
    let unit: PrsDiaryUnit?
    let teacher: PrsDiaryTeacher?
    let teacherFio: String?
    let subject: String?
    let part: [PrsDiaryPart]?
    let clazz: PrsDiaryClass?
}

struct PrsDiaryClass: Codable {
    let name: String?
}

struct PrsDiaryTeacher: Codable {
    let factTeacherIN: String?
    let lastName: String?
    let firstName: String?
    let middleName: String?

    var shortName: String {
        if let last = lastName, let first = firstName?.prefix(1), let mid = middleName?.prefix(1) {
            return "\(last) \(first).\(mid)."
        }
        return factTeacherIN ?? "Учитель"
    }

    var fullName: String {
        let parts = [lastName, firstName, middleName].compactMap { $0 }
        if !parts.isEmpty {
            return parts.joined(separator: " ")
        }
        return factTeacherIN ?? ""
    }
}

struct PrsDiaryUnit: Codable {
    let name: String?
    let short: String?
}

struct PrsDiaryPart: Codable {
    let cat: String?
    let variant: [PrsDiaryVariant]?
    let mrkWt: Double?
    let mark: [PrsDiaryMarkInPart]?
}

struct PrsDiaryMarkInPart: Codable {
    let markId: Int?
    let markValue: String?
    let markDt: String?
}

struct PrsDiaryVariant: Codable {
    let id: Int?
    let text: String?
    let file: [PrsDiaryFile]?
    let deadLine: Double?
}

struct PrsDiaryFile: Codable {
    let id: Int?
    let fileName: String?
}

struct PupilUnitsResponse: Codable {
    let result: [PupilUnit]?
}

struct PupilUnit: Codable {
    let unitId: String?
    let name: String?
    let shortName: String?
    let isOdod: Int?
}

struct LPartListPupilResponse: Codable {
    let result: [LPartTask]?
}

struct LPartTask: Codable {
    let passDt: Double?
    let unitName: String?
    let preview: String?
    let attachCnt: Int?
    let isDone: Int?
    let isVerified: Int?
}

struct ProfileNewResponse: Codable {
    let fio: String?
    let login: String?
    let birthDate: String?
    let data: ProfileNewData?
    let pupil: [ProfileNewPupil]?
    let prsRel: [ProfileNewRelation]?
}

struct ProfileNewData: Codable {
    let prsId: Int?
    let gender: Int?
}

struct ProfileNewPupil: Codable {
    let yearId: Int?
    let eduYear: String?
    let className: String?
    let bvt: String?
    let evt: String?
    let isReady: Int?
}

struct ProfileNewRelation: Codable {
    let relName: String?
    let data: ProfileNewRelationData?
}

struct ProfileNewRelationData: Codable {
    let lastName: String?
    let firstName: String?
    let middleName: String?
    let mobilePhone: String?
    let homePhone: String?
    let email: String?
}

struct UserSearchItem: Codable, Identifiable {
    var id: Int { prsId ?? 0 }
    let prsId: Int?
    let fio: String?
    let groupName: String?
    let isStudent: Int?
    let isEmp: Int?
    let isParent: Int?
    let imageId: Int?
    let pos: [UserPosition]?
}

struct UserPosition: Codable {
    let posTypeName: String?
}

struct GroupsTreeItem: Codable {
    let orgName: String?
    let groupTypeName: String?
    let groupName: String?
    let groups: [GroupsTreeItem]?
    let users: [GroupsTreeUser]?
}

struct GroupsTreeUser: Codable {
    let fio: String?
    let prsId: Int?
    let pos: [GroupsTreePosition]?
}

struct GroupsTreePosition: Codable {
    let posTypeName: String?
}

struct SendMessageResponse: Codable {

}