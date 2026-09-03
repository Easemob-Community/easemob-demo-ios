//
//  MineAlertMessageCell.swift
//  EaseChatDemo
//
//  AlertMessageCell 的 demo 定制:
//  为时间分割线提供居中、禁交互的展示;其余 alert 消息(撤回、置顶、话题等)维持原样。

import UIKit
import EaseChatUIKit

final class MineAlertMessageCell: AlertMessageCell {

    override func refresh(entity: MessageEntity) {
        guard MessageTimeDivider.isDivider(entity.message) else {
            // 复用的分割线 cell 恢复默认状态
            self.content.isHidden = false
            self.content.isUserInteractionEnabled = true
            super.refresh(entity: entity)
            return
        }
        self.checkbox.isHidden = true
        self.entity = entity
        self.content.attributedText = nil
        self.content.isHidden = true
        // 禁用手势,避免分割线弹出长按菜单/点击进入话题
        self.content.isUserInteractionEnabled = false
        self.time.text = entity.message.showDate
        self.time.frame = CGRect(x: 16, y: 10, width: EaseChatUIKit.ScreenWidth - 32, height: 16)
    }
}
