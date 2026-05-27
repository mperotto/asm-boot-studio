import {EditorState, Compartment} from '@codemirror/state';
import {EditorView, keymap, lineNumbers, highlightActiveLine, highlightActiveLineGutter, drawSelection} from '@codemirror/view';
import {defaultKeymap, history, historyKeymap, indentWithTab} from '@codemirror/commands';
import {searchKeymap, highlightSelectionMatches} from '@codemirror/search';
import {autocompletion, completionKeymap, closeBrackets, snippetCompletion} from '@codemirror/autocomplete';
import {StreamLanguage, syntaxHighlighting, HighlightStyle, indentUnit} from '@codemirror/language';
import {tags as t} from '@lezer/highlight';

const INSTRUCTIONS = [
  'aaa','aad','aam','aas','adc','add','and','call','cbw','clc','cld','cli','cmc','cmp','cmpsb','cmpsw','cwd','daa','das',
  'dec','div','hlt','idiv','imul','in','inc','int','iret','ja','jae','jb','jbe','jc','jcxz','je','jg','jge','jl','jle',
  'jmp','jna','jnae','jnb','jnbe','jnc','jne','jno','jnp','jns','jnz','jo','jp','jpe','jpo','js','jz','lahf','lds',
  'lea','les','lodsb','lodsw','loop','loope','loopne','loopnz','loopz','mov','movsb','movsw','mul','neg','nop','not',
  'or','out','pop','popa','popf','push','pusha','pushf','rcl','rcr','ret','retf','rol','ror','sahf','sal','sar','sbb',
  'scasb','scasw','shl','shr','stc','std','sti','stosb','stosw','sub','test','xchg','xlat','xor'
];

const REGISTERS = [
  'ax','bx','cx','dx','sp','bp','si','di','al','ah','bl','bh','cl','ch','dl','dh',
  'cs','ds','es','ss','fs','gs','eax','ebx','ecx','edx','esp','ebp','esi','edi',
  'cr0','cr2','cr3','cr4'
];

const DIRECTIVES = [
  'bits','org','equ','times','db','dw','dd','dq','resb','resw','resd','section','segment','global','extern','%define',
  '%include','%macro','%endmacro','%if','%ifdef','%ifndef','%else','%endif'
];

const BIOS_COMPLETIONS = [
  {label:'int 0x10',type:'function',detail:'BIOS video services',apply:'int 0x10'},
  {label:'int 0x13',type:'function',detail:'BIOS disk services',apply:'int 0x13'},
  {label:'int 0x16',type:'function',detail:'BIOS keyboard services',apply:'int 0x16'},
  {label:'ah 0x0e',type:'constant',detail:'teletype output',apply:'ah, 0x0e'},
  {label:'ah 0x02',type:'constant',detail:'read disk sectors',apply:'ah, 0x02'},
  {label:'0xAA55',type:'constant',detail:'boot signature',apply:'0xAA55'},
  {label:'0x7c00',type:'constant',detail:'boot load address',apply:'0x7c00'}
];

const SNIPPETS = [
  snippetCompletion('org 0x7c00\nbits 16\n\n${start}:\n    ${}\n\ntimes 510-($ - $$) db 0\ndw 0xAA55', {
    label:'boot sector',
    type:'text',
    detail:'NASM boot sector template'
  }),
  snippetCompletion('print:\n    lodsb\n    or al, al\n    jz .done\n    mov ah, 0x0e\n    mov bx, 0x0007\n    int 0x10\n    jmp print\n.done:\n    ret', {
    label:'print routine',
    type:'function',
    detail:'BIOS teletype string loop'
  }),
  snippetCompletion('mov ah, 0x02\nmov al, ${1:1}\nmov ch, ${2:0}\nmov cl, ${3:2}\nmov dh, ${4:0}\nmov dl, [boot_drive]\nint 0x13\njc ${5:disk_error}', {
    label:'read sector',
    type:'function',
    detail:'BIOS int 13h sector read'
  })
];

const asmLanguage = StreamLanguage.define({
  name:'nasm',
  startState(){
    return {};
  },
  token(stream){
    if(stream.eatSpace())return null;
    if(stream.match(';')){
      stream.skipToEnd();
      return 'comment';
    }
    if(stream.match(/'(?:[^'\\]|\\.)*'?/)||stream.match(/"(?:[^"\\]|\\.)*"?/))return 'string';
    if(stream.match(/^[A-Za-z_.%$][\w.$%]*:/))return 'labelName';
    if(stream.match(/^\[[^\]]*\]/))return 'squareBracket';
    if(stream.match(/^0x[0-9a-fA-F]+|^[0-9a-fA-F]+h\b|^\d+\b/))return 'number';
    if(stream.match(/^[+\-*/(),:]/))return 'punctuation';

    const word=stream.match(/^[A-Za-z_.%][\w.%]*/);
    if(word){
      const lower=word[0].toLowerCase();
      if(INSTRUCTIONS.includes(lower))return 'keyword';
      if(REGISTERS.includes(lower))return 'atom';
      if(DIRECTIVES.includes(lower))return 'definitionKeyword';
      return 'variableName';
    }

    stream.next();
    return null;
  },
  languageData:{
    commentTokens:{line:';'},
    closeBrackets:{brackets:['(', '[', "'", '"']}
  }
});

const asmHighlight = HighlightStyle.define([
  {tag:t.keyword,color:'#ffb86c'},
  {tag:t.definitionKeyword,color:'#79c0ff'},
  {tag:t.atom,color:'#ffa657'},
  {tag:t.number,color:'#a5d6ff'},
  {tag:t.string,color:'#a5d6a7'},
  {tag:t.comment,color:'#8b949e',fontStyle:'italic'},
  {tag:t.labelName,color:'#d2a8ff'},
  {tag:t.variableName,color:'#e6edf3'},
  {tag:t.squareBracket,color:'#f0f6fc'},
  {tag:t.punctuation,color:'#c9d1d9'}
]);

const asmTheme = EditorView.theme({
  '&':{
    height:'100%',
    backgroundColor:'#0d1117',
    color:'#e6edf3',
    fontSize:'12px'
  },
  '.cm-scroller':{
    fontFamily:"'Courier New', monospace",
    lineHeight:'20px'
  },
  '.cm-content':{
    padding:'10px 12px',
    caretColor:'#58a6ff'
  },
  '.cm-gutters':{
    backgroundColor:'#0d1117',
    color:'#484f58',
    borderRight:'1px solid #161b22'
  },
  '.cm-activeLineGutter':{
    backgroundColor:'#161b22',
    color:'#8b949e'
  },
  '.cm-activeLine':{
    backgroundColor:'#161b2280'
  },
  '.cm-selectionBackground, &.cm-focused .cm-selectionBackground':{
    backgroundColor:'#264f78'
  },
  '.cm-cursor':{
    borderLeftColor:'#58a6ff'
  },
  '.cm-tooltip':{
    backgroundColor:'#161b22',
    color:'#c9d1d9',
    border:'1px solid #30363d',
    borderRadius:'6px',
    boxShadow:'0 12px 28px rgba(0,0,0,.35)'
  },
  '.cm-tooltip-autocomplete ul li[aria-selected]':{
    backgroundColor:'#1f6feb',
    color:'#fff'
  },
  '.cm-completionDetail':{
    color:'#8b949e'
  },
  '.cm-search':{
    backgroundColor:'#161b22',
    color:'#c9d1d9',
    border:'1px solid #30363d'
  },
  '.cm-search input':{
    backgroundColor:'#0d1117',
    color:'#c9d1d9',
    border:'1px solid #30363d'
  }
}, {dark:true});

function asmCompletions(context){
  const word=context.matchBefore(/[A-Za-z_.%0-9$]+/);
  if(!word&&!context.explicit)return null;
  const from=word?word.from:context.pos;
  return {
    from,
    options:[
      ...SNIPPETS,
      ...INSTRUCTIONS.map(label=>({label,type:'keyword',detail:'x86 instruction'})),
      ...REGISTERS.map(label=>({label,type:'variable',detail:'register'})),
      ...DIRECTIVES.map(label=>({label,type:'constant',detail:'NASM directive'})),
      ...BIOS_COMPLETIONS
    ],
    validFor:/^[A-Za-z_.%0-9$]*$/
  };
}

export function createAsmEditor({parent, doc='', onChange=()=>{}}){
  const tabSize=new Compartment();
  const state=EditorState.create({
    doc,
    extensions:[
      lineNumbers(),
      highlightActiveLineGutter(),
      history(),
      drawSelection(),
      EditorState.allowMultipleSelections.of(true),
      indentUnit.of('    '),
      tabSize.of(EditorState.tabSize.of(4)),
      asmLanguage,
      syntaxHighlighting(asmHighlight),
      closeBrackets(),
      autocompletion({
        override:[asmCompletions],
        activateOnTyping:true,
        defaultKeymap:true
      }),
      highlightSelectionMatches(),
      keymap.of([
        indentWithTab,
        ...defaultKeymap,
        ...historyKeymap,
        ...searchKeymap,
        ...completionKeymap
      ]),
      asmTheme,
      EditorView.lineWrapping,
      EditorView.updateListener.of(update=>{
        if(update.docChanged)onChange(update.state.doc.toString());
      })
    ]
  });

  const view=new EditorView({state,parent});
  return {
    view,
    getValue(){
      return view.state.doc.toString();
    },
    setValue(value){
      const current=view.state.doc.toString();
      if(current===value)return;
      view.dispatch({
        changes:{from:0,to:current.length,insert:value}
      });
    },
    focus(){
      view.focus();
    }
  };
}
