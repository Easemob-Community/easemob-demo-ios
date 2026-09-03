//
//  MineMessageListView.swift
//  EaseChatDemo
//
//  消息列表定制:按时间间隔注入"时间分割线"(非持久化),
//  并重写分页锚点使其跳过注入的分割线消息。

import UIKit
import EaseChatUIKit

final class MineMessageListView: MessageListView {

    /// 分页锚点必须指向真实消息,否则加载更多历史会以分割线的 messageId 作为游标
    override public var firstMessageId: String {
        self.dataSource.first { !MessageTimeDivider.isDivider($0) }?.messageId ?? ""
    }

    override public func refreshMessages(messages: [ChatMessage]) {
        super.refreshMessages(messages: MessageTimeDivider.insert(into: messages))
    }

    override public func insertMessages(messages: [ChatMessage]) {
        var batch = MessageTimeDivider.insert(into: messages)
        // 该页消息与当前列表第一条消息之间的边界也需要判断
        if let currentFirst = self.dataSource.first(where: { !MessageTimeDivider.isDivider($0) }),
            let lastNew = batch.last(where: { !MessageTimeDivider.isDivider($0) }),
            MessageTimeDivider.needsDivider(prev: lastNew, next: currentFirst)
        {
            batch.append(MessageTimeDivider.dividerMessage(for: currentFirst))
        }
        super.insertMessages(messages: batch)
    }

    override public func showMessage(message: ChatMessage) {
        if !MessageTimeDivider.isDivider(message) {
            let realMessages = self.dataSource.filter { !MessageTimeDivider.isDivider($0) }
            if realMessages.isEmpty {
                // 会话内首条消息也展示时间
                super.showMessage(message: MessageTimeDivider.dividerMessage(for: message))
            } else if let last = realMessages.last,
                MessageTimeDivider.needsDivider(prev: last, next: message)
            {
                super.showMessage(message: MessageTimeDivider.dividerMessage(for: message))
            }
        }
        super.showMessage(message: message)
    }
}
