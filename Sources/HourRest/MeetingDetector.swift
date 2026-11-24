import CoreMediaIO
import Foundation

/// 会议检测（DESIGN.md §9.4 渐进方案的第 2 步）：任一摄像头正被其他应用使用即视为在开会。
/// 读取的是「设备是否在运行」属性，不打开摄像头，也不需要摄像头权限。
///
/// 未覆盖：纯语音会议、屏幕共享、不开摄像头的演示。麦克风状态容易被常驻语音类应用误判，
/// 会导致提醒被一直顺延，因此没有纳入。
struct MeetingDetector {
    func isInMeeting() -> Bool {
        cameraInUse()
    }

    private func cameraInUse() -> Bool {
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var devicesAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &devicesAddress, 0, nil, &size) == noErr, size > 0 else { return false }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &devicesAddress, 0, nil, size, &used, &devices) == noErr else { return false }
        // 两次调用之间可能有设备拔出，只遍历实际返回的部分。
        devices = Array(devices.prefix(Int(used) / MemoryLayout<CMIOObjectID>.size))

        var runningAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard)
        )
        for device in devices {
            var running: UInt32 = 0
            var got: UInt32 = 0
            let status = CMIOObjectGetPropertyData(device, &runningAddress, 0, nil,
                                                   UInt32(MemoryLayout<UInt32>.size), &got, &running)
            if status == noErr, running != 0 { return true }
        }
        return false
    }
}
