# 总结

点击[这里](https://github.com/fzzjj2008/fzzjj2008.github.io/tree/main/docs/frontend/css/css.xmind)下载

```mindmap
CSS
  CSS简介
    基本概念：层叠样式表，用于设计风格和布局
    基本语法
      选择器 { 属性: 属性值; }
    引用方式
      行内样式表
        <div style="color: red; font-size: 12px">行内样式表</div>
      内部样式表
        <style>放在<header>内部
      外部样式表
        单独写在css文件中
        <link rel="stylesheet" href="css文件路径" />
  选择器
    基础选择器
      标签选择器
        标签 { 属性: 属性值 }
      类选择器
        .类名 { 属性1: 属性值1; }
      id选择器
        #标签 { 属性: 属性值 }
      通用选择器
        * { 属性1: 属性值1; }
    复合选择器
      后代选择器
        父元素 子元素 { 样式声明; }
      子代选择器
        父元素>子元素 { 样式声明; }
      并集选择器
        父元素 子元素 { 样式声明; }
      伪类选择器
        父元素 子元素 { 样式声明; }
    选择器优先级（重点）
      层叠性
      继承性
      优先级
  属性
    属性的书写顺序
      布局、自身、文本、渲染
    字体
    文本
    背景
    元素的显示和隐藏
      display、visibility、overflow
    ...
  元素显示模式
    块元素
      独占一行，可设置宽高
    行内元素
      一行可含多个块，不能设置宽高
    行内块元素
      一行可含多个块，可设置宽高
    display: block | inline | inline-block;
  文档流
    标准流
      盒子模型
        border、padding、margin、content
        外边距合并特例
          邻块元素垂直外边距合并
          嵌套块元素垂直外边距的塌陷
    浮动流
      为什么需要浮动？
      设置浮动
        float: left | right;
      浮动特性
        脱标
        顶部对齐
        行内块元素特性
      清除浮动
        约束浮动的影响
        clear: both;
    定位流
      为什么需要定位？
      设置定位
        static、relative、absolute、fixed、sticky
      定位的叠放
        z-index
      定位特性
        完全压住盒子
        行内块特性
  CSS高级用法
    精灵图
    字体图标
    CSS三角
    文字溢出
    布局技巧
    CSS初始化
      * { margin: 0; padding: 0; }
      ...
```

