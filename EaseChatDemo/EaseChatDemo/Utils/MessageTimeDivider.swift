//
//  MessageTimeDivider.swift
//  EaseChatDemo
//
//  时间分割线:以非持久化的 alert 消息形式注入消息列表。
//  相邻消息间隔超过阈值或跨天时,在后一条消息前插入一条分割线,仅在 UI 层展示,不落库、不发送。

import Foundation
import EaseChatUIKit
import HyphenateChat

enum MessageTimeDivider {

    /// 分割线在消息 ext 中的标记字段
    static let markerKey = "em_time_divider"

    /// 相邻消息超过该间隔(毫秒)则插入分割线
    static let interval: Int64 = 5 * 60 * 1000

    static func isDivider(_ message: ChatMessage) -> Bool {
        guard let body = message.body as? ChatCustomMessageBody else { return false }
        return body.event == EaseChatUIKit_alert_message
            && message.ext?[Self.markerKey] as? Bool == true
    }

    /// 构造挂在指定消息上的分割线消息,不落库、不发送。
    static func dividerMessage(for message: ChatMessage) -> ChatMessage {
        let body = ChatCustomMessageBody(event: EaseChatUIKit_alert_message, customExt: nil)
        let divider = ChatMessage(
            conversationID: message.conversationId, body: body, ext: [Self.markerKey: true])
        divider.messageId = "\(Self.markerKey)_\(message.messageId)"
        divider.timestamp = message.timestamp
        divider.localTime = message.localTime
        divider.direction = .send
        divider.chatType = message.chatType
        divider.status = .succeed
        return divider
    }

    /// 相邻两条消息之间是否需要分割线。
    static func needsDivider(prev: ChatMessage, next: ChatMessage) -> Bool {
        if abs(next.timestamp - prev.timestamp) > Self.interval { return true }
        let prevDate = Date(timeIntervalSince1970: TimeInterval(prev.timestamp / 1000))
        let nextDate = Date(timeIntervalSince1970: TimeInterval(next.timestamp / 1000))
        return !Calendar.current.isDate(prevDate, inSameDayAs: nextDate)
    }

    /// 为一页按时间升序的消息插入分割线(该页首条消息前必插)。
    static func insert(into messages: [ChatMessage]) -> [ChatMessage] {
        var result = [ChatMessage]()
        var previous: ChatMessage?
        for message in messages where !Self.isDivider(message) {
            if previous == nil || Self.needsDivider(prev: previous!, next: message) {
                result.append(Self.dividerMessage(for: message))
            }
            result.append(message)
            previous = message
        }
        return result
    }
}
